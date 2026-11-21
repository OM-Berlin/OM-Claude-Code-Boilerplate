#!/usr/bin/env bash
# PreToolUse-Hook: Sperrt eine kleine Liste von Befehlen, die Arbeit von Tagen
# zerstören oder Schlüssel offenlegen können:
#
#   - rekursives Löschen von / oder dem eigenen Home-Ordner: rm -r, Remove-Item -Recurse
#     und seine Kurznamen (ri, rd, rmdir, del, erase), dazu rd, rmdir, del und erase mit /s
#     aus cmd. Unter Windows zählen auch ein ganzes Laufwerk (C:\, /c) und der Benutzerordner
#     in den üblichen Schreibweisen (C:\Users\name, /c/Users/name, %USERPROFILE%,
#     $env:USERPROFILE, ${env:USERPROFILE}, $HOME, ~, auch mit \* oder /* dahinter,
#     Großschreibung egal)
#   - git push --force (oder -f, +main) auf main oder master
#   - git reset --hard, git clean -f sowie git checkout . und git restore . (verwerfen
#     alle ungesicherten Änderungen; einzelne Dateien und Branch-Wechsel bleiben erlaubt)
#   - einer dieser Befehle verpackt in bash -c, sh -c, cmd /c, cmd /k, powershell -Command,
#     pwsh -c oder Invoke-Expression; powershell -EncodedCommand lässt sich nicht prüfen und
#     ist immer gesperrt
#   - Lesen von .env-Dateien, Großschreibung egal: cat, type, Get-Content, Select-String,
#     findstr, diff, cmp und so weiter; rekursives grep über den ganzen Ordner ohne
#     --exclude; Select-String oder findstr über * oder *.*; Get-ChildItem über den ganzen
#     Ordner ohne -Exclude, weitergereicht an Select-String oder Get-Content; Read-Werkzeug
#     auf .env.local, Grep-Werkzeug mit glob .env*. .env.example bleibt lesbar, dort stehen
#     nur Platzhalter
#   - Aufrufe, deren JSON ein Zeichen U+0000 oder ein halbes Unicode-Paar enthält (nicht prüfbar)
#
# So funktioniert er: Claude Code schickt vor jedem Aufruf von Bash, PowerShell (nur
# Windows), Read oder Grep
# ein JSON auf stdin. Passt der Befehl zur Liste, endet der Hook mit Exitcode 2.
# Dann bricht Claude Code den Aufruf ab und zeigt Claude die Meldung von stderr.
# Claude liest den Grund und sucht einen anderen Weg. Jeder andere Exitcode lässt
# den Aufruf durch. Der Hook führt nie etwas aus der Eingabe aus, er liest sie nur.
#
# Warum ein Hook statt einer Regel: Eine Regel in CLAUDE.md befolgt Claude meistens,
# ein Hook greift jedes Mal. Er ist eine Bremse gegen Versehen, keine
# Sicherheitsgrenze: Wer will, kommt mit Umwegen (etwa einem Skript) daran vorbei.
#
# JSON statt Exitcode: Mit HOOK_AUSGABE=json meldet der Hook eine Sperre als JSON auf
# stdout (hookSpecificOutput, permissionDecision deny) und endet mit 0. Das nutzt Codex unter
# Windows (.codex/hooks.json, commandWindows), weil PowerShell aus Exitcode 2 eine 1 macht.
#
# Abschalten: Steht die Umgebungsvariable OM_SCHUTZ_HOOK auf "aus", lässt der Hook alles
# durch. Jeder andere Wert und kein Wert heißt an. Claude Code setzt sie aus dem Block
# "env" in .claude/settings.json; Codex, Antigravity und Pi erben sie aus der Shell, in der
# sie gestartet wurden.
#
# Tempo: Manche Programme geben einem Hook nur wenige Sekunden und lassen den Befehl danach
# ungeprüft laufen. Unter Git Bash kostet jeder Extra-Prozess ein Vielfaches von macOS.
# Deshalb startet der Hook pro Argument keinen Prozess, nur bash-eigene Mittel.
#
# Selbst testen:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}' \
#     | bash .claude/hooks/block-dangerous-commands.sh; echo "Exitcode: $?"
# Tests: bash .claude/hooks/tests/test-block-dangerous-commands.sh
# Nur bash, sed, head und tr; läuft auf macOS (bash 3.2) und unter Git Bash auf Windows.
set -uo pipefail
set -f # Wörter wie * nicht als Dateinamen auflösen

if [ "${OM_SCHUTZ_HOOK:-}" = "aus" ]; then
  cat >/dev/null 2>&1 # Eingabe abnehmen, damit der Aufrufer nicht in eine geschlossene Leitung schreibt
  exit 0
fi

# Byteweise arbeiten: In einer UTF-8-Umgebung brechen tr und sed bei ungültigen Bytes ab,
# und der Hook ließe den Aufruf ungeprüft durch. Mit LC_ALL=C ist jedes Byte ein Zeichen.
export LC_ALL=C

BLOCKED_EXIT=2
# Befehlsnamen vergleicht der Hook ohne Rücksicht auf Großschreibung (PowerShell kennt keine).
READERS=" cat less more head tail bat nl grep egrep fgrep rg sed awk source . xxd od strings base64 cut sort uniq type get-content gc select-string sls findstr diff cmp vimdiff colordiff "
PREFIXES=" sudo env command nohup time exec builtin { "
BS='\'
SQ="'"
DQ='"'
printf -v NL '\012'
printf -v PIPE_MARK '\036' # steht nach dem Zerlegen dort, wo im Befehl ein | stand

payload="$(tr '\r\n' '  ')"
project="${CLAUDE_PROJECT_DIR:-$PWD}"
project="${project//\\//}"
project="${project%/}"

# Home-Ordner einmal vorbereiten: / statt \, ohne / am Ende; dazu die Git-Bash-Form /c/Users/name.
HOME_N="${HOME:-}"
HOME_N="${HOME_N//\\//}"
HOME_N="${HOME_N%/}"
UP_N="${USERPROFILE:-}"
UP_N="${UP_N//\\//}"
UP_N="${UP_N%/}"
UP_GB=""
case "$UP_N" in [A-Za-z]:/*) UP_GB="/${UP_N%%:*}/${UP_N#?:/}" ;; esac

block() {
  local reason="Gesperrt vom Hook block-dangerous-commands.sh: $1"
  echo "$reason" >&2
  if [ "${HOOK_AUSGABE:-}" = json ]; then
    reason="$(printf '%s' "$reason" | tr '\t\r\n' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
    exit 0
  fi
  exit "$BLOCKED_EXIT"
}

ENV_REASON=".env-Dateien enthalten Schlüssel und bleiben ungelesen. Die Namen der Variablen stehen in .env.example. Braucht ein Programm einen Wert, liest es ihn selbst aus .env.local."

# Roher String-Wert zu einem JSON-Schlüssel, Escapes noch nicht aufgelöst.
json_raw() {
  printf '%s' "$payload" |
    sed -E -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' |
    head -n 1
}

# Hängt die UTF-8-Bytes eines Codepunkts an U8 an.
utf8_byte() { local h; printf -v h '%02x' "$1"; printf -v h "${BS}x$h"; U8="$U8$h"; }
utf8() {
  local c="$1"
  U8=""
  if [ "$c" -lt 128 ]; then utf8_byte "$c"
  elif [ "$c" -lt 2048 ]; then utf8_byte $((192 | c >> 6)); utf8_byte $((128 | c & 63))
  elif [ "$c" -lt 65536 ]; then
    utf8_byte $((224 | c >> 12)); utf8_byte $((128 | (c >> 6) & 63)); utf8_byte $((128 | c & 63))
  else
    utf8_byte $((240 | c >> 18)); utf8_byte $((128 | (c >> 12) & 63))
    utf8_byte $((128 | (c >> 6) & 63)); utf8_byte $((128 | c & 63))
  fi
}

# JSON-Text zu Klartext in einem einzigen Durchgang, Ergebnis in DECODED. Der Text wird an
# jedem Backslash in Stücke geteilt (read mit IFS, linear auch bei Hunderten Windows-Pfaden;
# Muster-Ersetzung mit ${text//...} wäre in bash 3.2 quadratisch). Jedes Stück hinter einem
# einleitenden Backslash beginnt mit dem Escape-Zeichen. Ein leeres Stück heißt
# Backslash-Backslash: ein Backslash, und das Stück danach ist gewöhnlicher Text. So bleibt
# C:\new\app (im JSON C:\\new\\app) ein Pfad und wird nicht zu C: plus Zeilenumbruch.
# Zeilenumbruch bleibt Zeilenumbruch, Tab und die übrigen Steuerzeichen werden Leerzeichen,
# Backslash-u mit vier Hexziffern wird zum Zeichen (UTF-8). U+0000, ein halbes Unicode-Paar
# und Backslash-u ohne vier Hexziffern lassen sich nicht sicher prüfen: Dann ist UNREADABLE=1.
DECODED=""
UNREADABLE=0
json_decode() {
  local p rest cp esc=1 first=1 hi=0 IFS
  local -a parts buf
  UNREADABLE=0
  buf=()
  IFS="$BS" read -r -a parts <<<"${1}x" # x: damit ein Backslash am Ende sein Stück behält
  for p in "${parts[@]}"; do
    if [ "$first" = 1 ]; then first=0; buf+=("$p"); continue; fi
    if [ "$esc" = 0 ]; then buf+=("$p"); esc=1; continue; fi
    if [ "$hi" != 0 ]; then # zweite Hälfte eines Unicode-Paars erwartet
      case "$p" in
        u[dD][c-fC-F][0-9a-fA-F][0-9a-fA-F]*)
          cp=$((65536 + ((hi - 55296) << 10) + (16#${p:1:4} - 56320)))
          hi=0
          utf8 "$cp"; buf+=("$U8${p:5}"); continue ;;
      esac
      hi=0; UNREADABLE=1
    fi
    case "$p" in
      "") buf+=("$BS"); esc=0 ;; # Backslash-Backslash
      n*) buf+=("$NL${p:1}") ;;
      [trbf]*) buf+=(" ${p:1}") ;;
      "$DQ"* | /*) buf+=("$p") ;;
      u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*)
        cp=$((16#${p:1:4}))
        rest="${p:5}"
        if [ "$cp" -ge 55296 ] && [ "$cp" -le 56319 ]; then
          hi="$cp"
          [ -z "$rest" ] || { UNREADABLE=1; hi=0; buf+=("$rest"); }
          continue
        fi
        case "$cp" in
          0) UNREADABLE=1; buf+=("$rest") ;;
          10) buf+=("$NL$rest") ;;
          [1-9] | 1[1-9] | 2[0-9] | 3[01]) buf+=(" $rest") ;;
          *)
            [ "$cp" -ge 56320 ] && [ "$cp" -le 57343 ] && UNREADABLE=1
            utf8 "$cp"; buf+=("$U8$rest") ;;
        esac ;;
      u*) UNREADABLE=1; buf+=("${p:1}") ;;
      *) buf+=("$BS$p") ;; # unbekanntes Escape bleibt, wie es ist
    esac
  done
  [ "$hi" = 0 ] || UNREADABLE=1
  IFS=""
  DECODED="${buf[*]}"
  DECODED="${DECODED%x}"
}

# Wert eines Feldes aus tool_input in DECODED; nicht prüfbare Schreibweise sperrt.
field() {
  json_decode "$(json_raw "$1")"
  [ "$UNREADABLE" = 0 ] ||
    block "Der Aufruf enthält eine Unicode-Schreibweise (Backslash, u und vier Ziffern für U+0000 oder ein halbes Zeichenpaar), die sich nicht sicher prüfen lässt. Schreib den Befehl oder den Pfad mit normalen Zeichen."
}

# Entfernt alle Anführungszeichen, Ergebnis in UQ (ohne Extra-Prozess).
unq() {
  UQ="${1//\"/}"
  UQ="${UQ//$SQ/}"
}

is_env_file() {
  local r=1 base
  unq "${1//\\//}" # Windows-Pfade: \ wird zu /
  base="${UQ##*/}"
  shopt -s nocasematch
  case "$base" in
    *.example | *.sample | *.template | .env.example*) ;;
    .env | .env.* | *.env) r=0 ;;
    .env*) case "$base" in *[*?[]*) r=0 ;; esac ;; # Muster wie .env*
  esac
  shopt -u nocasematch
  return "$r"
}

# / oder Laufwerk oder Home-Ordner, auch mit /, /* oder /. dahinter, Großschreibung egal.
is_root_or_home() {
  local t core r=1
  unq "$1"
  t="${UQ//\\//}" # Windows-Pfade: \ wird zu /
  [ -n "$t" ] || return 1
  core="$t"
  while :; do
    case "$core" in
      */) core="${core%/}" ;;
      */\*) core="${core%/\*}" ;;
      */.) core="${core%/.}" ;;
      *) break ;;
    esac
  done
  shopt -s nocasematch
  case "$core" in
    "" | [a-z]: | /[a-z]) r=0 ;; # /, Laufwerk C: oder /c in Git Bash
    '~' | '$HOME' | '${HOME}' | '$env:HOME' | '${env:HOME}') r=0 ;;
    '$USERPROFILE' | '${USERPROFILE}' | '$env:USERPROFILE' | '${env:USERPROFILE}' | '%USERPROFILE%') r=0 ;;
  esac
  if [ "$r" = 1 ]; then
    if [ -n "$HOME_N" ] && [[ $core == "$HOME_N" ]]; then
      r=0
    elif [ -n "$UP_N" ] && [[ $core == "$UP_N" ]]; then
      r=0
    elif [ -n "$UP_GB" ] && [[ $core == "$UP_GB" ]]; then
      r=0
    fi
  fi
  shopt -u nocasematch
  return "$r"
}

# Muster für das Grep-Werkzeug (Feld glob), etwa **/.env* oder *.{js,env}.
is_env_glob() {
  local base r=1
  is_env_file "$1" && return 0
  unq "${1//\\//}"
  base="${UQ##*/}"
  shopt -s nocasematch
  case "$base" in
    *.example* | *.sample* | *.template*) ;;
    *[*?[{]*) case "$base" in *.env* | *"{env"* | *",env"*) r=0 ;; esac ;;
  esac
  shopt -u nocasematch
  return "$r"
}

# Ziel einer Suche, das den ganzen Ordner (und damit .env-Dateien) einschließt.
is_wide_target() {
  local t
  is_root_or_home "$1" && return 0
  unq "${1//\\//}"
  t="${UQ%/}"
  case "$t" in . | ./\* | \* | .. | ../\* | \*.\* | ./\*.\* | \*\* | \*\*/\* | ./\*\*) return 0 ;; esac
  [ "$t" = "$project" ] && return 0
  return 1
}

# Rekursives grep (-r, -R, --recursive) über den ganzen Ordner liest auch .env-Dateien,
# außer eine --exclude-Angabe nimmt sie aus. Einzelne Unterordner wie src bleiben frei.
check_grep_recursive() { # check_grep_recursive <args nach grep>
  local a prev="" recursive=0 positional=0 has_pattern_opt=0 wide=0
  for a in "$@"; do
    unq "$a"; a="$UQ"
    case "$a" in
      --recursive | --dereference-recursive) recursive=1 ;;
      --exclude=*env* | --exclude=*ENV*) return 0 ;;
      --regexp | --regexp=* | --file | --file=*) has_pattern_opt=1 ;;
      --*) ;;
      -*) case "$a" in *[rR]*) recursive=1 ;; esac
          case "$a" in *[ef]) has_pattern_opt=1 ;; esac ;;
      *)
        if [ "$prev" = "--exclude" ]; then
          case "$a" in *env* | *ENV*) return 0 ;; esac
        else
          positional=$((positional + 1))
          is_wide_target "$a" && wide=1
        fi ;;
    esac
    prev="$a"
  done
  [ "$recursive" = 1 ] || return 0
  # Ohne Ziel durchsucht GNU grep -r den aktuellen Ordner; das erste Wort ist das Suchmuster.
  [ "$has_pattern_opt" = 1 ] || positional=$((positional - 1))
  [ "$positional" -le 0 ] && wide=1
  [ "$wide" = 1 ] &&
    block "Rekursives grep über den ganzen Ordner liest auch .env-Dateien mit Schlüsseln. Suche in einem Unterordner wie src oder schließe die Dateien mit --exclude='.env*' aus."
  return 0
}

# Schalter aus cmd wie /s, /q, /a:h oder /s/q (kein Pfad).
is_cmd_switch() {
  case "$1" in
    /[A-Za-z?] | /[A-Za-z?]:* | /[A-Za-z]/[A-Za-z] | /[A-Za-z]/[A-Za-z]/[A-Za-z]) return 0 ;;
  esac
  return 1
}

check_rm() { # check_rm <cmd-Schreibweise 0|1> <args...>
  local style="$1" recursive=0 a targets=""
  shift
  for a in "$@"; do
    unq "$a"
    case "$UQ" in
      --recursive) recursive=1 ;;
      --*) ;;
      -*) case "$UQ" in *[rR]*) recursive=1 ;; esac ;; # -r, -rf, -Recurse
      *)
        if [ "$style" = 1 ] && is_cmd_switch "$UQ"; then # rd /s /q: /s heißt rekursiv
          case "$UQ/" in */[sS]/*) recursive=1 ;; esac
          continue
        fi
        is_root_or_home "$a" && targets="$a" ;;
    esac
  done
  [ "$recursive" = 1 ] && [ -n "$targets" ] &&
    block "rm -r auf '$targets' würde das ganze System oder den Home-Ordner löschen. Lösch nur einzelne Dateien im Projekt und frag vorher nach."
  return 0
}

is_whole_tree() { # "." und Verwandte: alle Dateien im Ordner
  unq "$1"
  case "$UQ" in . | ./ | ./\* | \* | :/ | :/.) return 0 ;; esac
  return 1
}

is_main() {
  local ref
  unq "${1#+}"
  ref="${UQ##*:}"
  ref="${ref#refs/heads/}"
  [ "$ref" = "main" ] || [ "$ref" = "master" ]
}

check_git() { # check_git <args nach "git">
  local dir="$project" sub="" force=0 all=0 a positional=0 skip=0 hits_main=0 has_refspec=0
  local staged=0 worktree=0
  while [ $# -gt 0 ]; do
    unq "$1"
    case "$UQ" in
      -C) unq "${2:-}"; dir="$UQ"; shift 2 || shift; continue ;;
      -c) shift 2 || shift; continue ;;
      -*) shift; continue ;;
    esac
    sub="$UQ"; shift; break
  done
  case "$sub" in
    clean)
      for a in "$@"; do
        unq "$a"
        case "$UQ" in
          --force) block "git clean --force löscht ungesicherte Dateien endgültig. Nutze git clean -n für eine Vorschau und frag den Nutzer, bevor etwas gelöscht wird." ;;
          --*) ;;
          -*f*) block "git clean -f löscht ungesicherte Dateien endgültig. Nutze git clean -n für eine Vorschau und frag den Nutzer, bevor etwas gelöscht wird." ;;
        esac
      done
      ;;
    checkout | restore)
      for a in "$@"; do
        unq "$a"
        case "$UQ" in
          --staged) staged=1 ;;
          --worktree) worktree=1 ;;
          --*) ;;
          -*) case "$UQ" in *S*) staged=1 ;; esac
              case "$UQ" in *W*) worktree=1 ;; esac ;;
          *) is_whole_tree "$UQ" && all=1 ;;
        esac
      done
      # git restore --staged . nimmt Änderungen nur aus der Vormerkung, die Dateien bleiben.
      if [ "$all" = 1 ] && ! { [ "$sub" = restore ] && [ "$staged" = 1 ] && [ "$worktree" = 0 ]; }; then
        block "git $sub . verwirft alle nicht gesicherten Änderungen im Ordner. Nutze git stash, nenne einzelne Dateien oder frag den Nutzer, bevor etwas verworfen wird."
      fi
      ;;
    reset)
      for a in "$@"; do
        unq "$a"
        [ "$UQ" = "--hard" ] && block "git reset --hard verwirft alle nicht gesicherten Änderungen. Nutze git stash oder frag den Nutzer, bevor etwas verworfen wird."
      done
      ;;
    push)
      for a in "$@"; do
        unq "$a"; a="$UQ"
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$a" in
          --force | --force-with-lease* | --force-if-includes) force=1 ;;
          --all | --mirror) all=1 ;;
          -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
          --*) ;;
          -*) case "$a" in *f*) force=1 ;; esac ;;
          *)
            positional=$((positional + 1))
            [ "$positional" -eq 1 ] && continue # das erste ist der Remote, etwa origin
            has_refspec=1
            case "$a" in +*) force=1 ;; esac
            if [ "$a" = "HEAD" ]; then
              is_main "$(git -C "$dir" branch --show-current 2>/dev/null)" && hits_main=1
            else
              is_main "$a" && hits_main=1
            fi
            ;;
        esac
      done
      [ "$force" = 1 ] || return 0
      if [ "$has_refspec" = 0 ] && [ "$all" = 0 ]; then
        is_main "$(git -C "$dir" branch --show-current 2>/dev/null)" && hits_main=1
      fi
      { [ "$hits_main" = 1 ] || [ "$all" = 1 ]; } &&
        block "Erzwungenes Hochladen (force push) auf main oder master überschreibt Arbeit, die schon geteilt ist. Push ohne --force oder auf einen eigenen Branch."
      ;;
  esac
  return 0
}

check_env_read() { # check_env_read <wort...>
  local prev="" a
  for a in "$@"; do
    if [ "$prev" = "<" ] && is_env_file "$a"; then return 0; fi
    case "$a" in "<"?*) is_env_file "${a#<}" && return 0 ;; esac
    prev="$a"
  done
  return 1
}

# Select-String über alle Dateien (* oder *.*) oder hinter einer Liste des ganzen Ordners
# (Get-ChildItem | Select-String) liest auch .env-Dateien, außer -Exclude nimmt sie aus.
check_select_string() { # check_select_string <aus breiter Liste 0|1> <args...>
  local from_wide="$1" a expect="" pattern_given=0 positional=0 has_path=0 wide=0 excluded=0
  shift
  for a in "$@"; do
    unq "$a"; a="$UQ"
    if [ -n "$expect" ]; then
      case "$expect" in
        path) has_path=1; is_wide_target "$a" && wide=1 ;;
        exclude) case "$a" in *[eE][nN][vV]*) excluded=1 ;; esac ;;
      esac
      expect=""; continue
    fi
    shopt -s nocasematch
    case "$a" in
      -path | -literalpath | -lp | -pspath | -li*) expect=path ;;
      -path:* | -literalpath:*) has_path=1; is_wide_target "${a#*:}" && wide=1 ;;
      -pat*) expect=pattern; pattern_given=1 ;;
      -exc*) expect=exclude ;;
      -inc* | -enc* | -con* | -cul* | -inputobject) expect=other ;;
      -*) ;;
      *)
        positional=$((positional + 1))
        if [ "$pattern_given" = 1 ] || [ "$positional" -gt 1 ]; then
          has_path=1
          is_wide_target "$a" && wide=1
        fi ;;
    esac
    shopt -u nocasematch
  done
  [ "$excluded" = 1 ] && return 0
  [ "$has_path" = 0 ] && [ "$from_wide" = 1 ] && wide=1
  [ "$wide" = 1 ] &&
    block "Select-String über alle Dateien liest auch .env-Dateien mit Schlüsseln. Nenne einzelne Dateien oder einen Unterordner wie src, oder schließe die Dateien mit -Exclude '.env*' aus."
  return 0
}

# findstr über * oder *.* (mit oder ohne /s) liest unter Windows auch .env-Dateien.
check_findstr() {
  local a pattern_given=0 positional=0
  for a in "$@"; do
    unq "$a"; a="$UQ"
    case "$a" in
      /[cC]:*) pattern_given=1 ;;
      /[gG]:* | /[fF]:*) [ "${a:1:1}" = g ] || [ "${a:1:1}" = G ] && pattern_given=1
        is_env_file "${a:3}" && block "$ENV_REASON" ;;
      /*) ;;
      *)
        positional=$((positional + 1))
        if [ "$pattern_given" = 1 ] || [ "$positional" -gt 1 ]; then
          is_wide_target "$a" &&
            block "findstr über alle Dateien liest auch .env-Dateien mit Schlüsseln. Nenne einzelne Dateien oder Muster wie *.js oder src\\*.js."
        fi ;;
    esac
  done
  return 0
}

# Get-Content und type: hinter einer Liste des ganzen Ordners oder über * lesen sie auch .env.
check_get_content() { # check_get_content <aus breiter Liste 0|1> <args...>
  local from_wide="$1" a paths=0
  shift
  for a in "$@"; do
    unq "$a"
    case "$UQ" in
      -*) ;;
      *) paths=$((paths + 1))
         case "${UQ//\\//}" in \* | \*.\* | ./\* | ./\*.\*) block "$ENV_REASON" ;; esac ;;
    esac
  done
  [ "$from_wide" = 1 ] && [ "$paths" = 0 ] && block "$ENV_REASON"
  return 0
}

# Get-ChildItem (gci, dir, ls) über den ganzen Ordner ohne -Exclude, -Filter oder -Include:
# setzt LISTING_WIDE=1, damit ein folgendes | Select-String gesperrt wird.
LISTING_WIDE=0
check_listing() {
  local a expect="" paths=0 wide=0 limited=0
  for a in "$@"; do
    unq "$a"; a="$UQ"
    if [ -n "$expect" ]; then
      case "$expect" in
        path) paths=$((paths + 1)); is_wide_target "$a" && wide=1 ;;
        exclude) case "$a" in *[eE][nN][vV]*) limited=1 ;; esac ;;
        filter) case "$a" in \* | \*.\*) ;; *) is_env_glob "$a" || limited=1 ;; esac ;;
      esac
      expect=""; continue
    fi
    shopt -s nocasematch
    case "$a" in
      -path | -literalpath | -lp | -pspath | -li*) expect=path ;;
      -exc*) expect=exclude ;;
      -filt* | -inc*) expect=filter ;;
      -dep* | -att*) expect=other ;;
      -*) ;;
      *) paths=$((paths + 1)); is_wide_target "$a" && wide=1 ;;
    esac
    shopt -u nocasematch
  done
  [ "$paths" = 0 ] && wide=1 # ohne Pfad: der aktuelle Ordner
  [ "$limited" = 1 ] && wide=0
  LISTING_WIDE="$wide"
}

# Zerlegt einen Befehlstext an ; & ( ) und Backticks in Zeilen und jede Zeile an | in
# Stücke, und prüft jedes Stück. Ein Stück hinter | bekommt PIPED=1. Zerlegt wird mit
# einem einzigen tr und read, weil ${text//...} in bash 3.2 bei langen Texten quadratisch ist.
check_string() {
  local seg piece k
  local -a pieces
  PREV_WIDE=0
  while IFS= read -r seg; do
    pieces=()
    IFS="$PIPE_MARK" read -r -a pieces <<<"$seg"
    k=0
    for piece in ${pieces[@]+"${pieces[@]}"}; do
      PIPED="$k"
      k=1
      check_segment "$piece"
    done
  done <<<"$(printf '%s' "$1" | tr ';&()`|' '\n\n\n\n\n\036')"
}

check_inner() { # check_inner <wörter...>: prüft die Wörter ohne Anführungszeichen als eigenen Befehlstext
  local a inner=""
  for a in "$@"; do
    unq "$a"
    inner="$inner $UQ"
  done
  [ -n "$inner" ] && check_string "$inner"
  return 0
}

check_shell_c() { # check_shell_c <args nach bash/sh>: bash -c "..." prüft den Text im Argument
  local a found=0
  local -a inner=()
  for a in "$@"; do
    if [ "$found" = 1 ]; then inner+=("$a"); continue; fi
    unq "$a"
    case "$UQ" in -c | -[!-]*c*) found=1 ;; esac
  done
  check_inner ${inner[@]+"${inner[@]}"}
}

check_cmd_c() { # check_cmd_c <args nach cmd>: cmd /c "..." und cmd /k "..." prüfen den Text dahinter
  local a found=0
  local -a inner=()
  for a in "$@"; do
    if [ "$found" = 1 ]; then inner+=("${a//^/}"); continue; fi # ^ ist in cmd nur ein Escape-Zeichen
    case "$a" in
      /[cCkKrR]) found=1 ;;
      /[cCkKrR]\"*) found=1; inner+=("${a:2}") ;; # cmd /c"git ..."
    esac
  done
  check_inner ${inner[@]+"${inner[@]}"}
}

check_ps_c() { # check_ps_c <args nach powershell/pwsh>: -Command prüft den Text dahinter
  local a o found=0 skip=0
  local -a inner=()
  for a in "$@"; do
    if [ "$found" = 1 ]; then inner+=("$a"); continue; fi
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    unq "$a"; o="$UQ"
    case "$o" in --*) o="-${o#--}" ;; /*) o="-${o#/}" ;; esac
    shopt -s nocasematch
    case "$o" in
      -c | -co | -com | -comm | -comma | -comman | -command) found=1 ;;
      -e | -ec | -en | -enc | -enco | -encod | -encode | -encoded | -encodedc* | -encodeda* | -ea)
        shopt -u nocasematch
        block "powershell -EncodedCommand (auch -enc oder -e) enthält einen Befehl in Base64, den der Hook nicht prüfen kann. Schreib den Befehl im Klartext, etwa mit -Command." ;;
      -f | -fi | -fil | -file) shopt -u nocasematch; break ;; # ein Skript, keine Befehlszeile
      -ex* | -ep | -w* | -conf* | -o | -of | -out* | -inp* | -if | -ps* | -v | -ver* | -settings* | -custompipename) skip=1 ;;
      -*) ;;
      *) found=1; inner+=("$a") ;; # Windows PowerShell nimmt Wörter ohne Schalter als Befehl
    esac
    shopt -u nocasematch
  done
  check_inner ${inner[@]+"${inner[@]}"}
}

check_segment() {
  local -a words
  read -r -a words <<<"$1"
  local from_wide=0
  [ "$PIPED" = 1 ] && [ "$PREV_WIDE" = 1 ] && from_wide=1
  PREV_WIDE=0
  [ "${#words[@]}" -gt 0 ] || return 0
  local i=0 cmd
  while [ "$i" -lt "${#words[@]}" ]; do # Vorsätze wie sudo oder VAR=wert überspringen
    case "${words[$i]}" in
      *=*) i=$((i + 1)); continue ;;
    esac
    case "$PREFIXES" in *" ${words[$i]} "*) i=$((i + 1)); continue ;; esac
    break
  done
  [ "$i" -lt "${#words[@]}" ] || return 0
  unq "${words[$i]}"
  cmd="${UQ##*/}"   # /bin/rm zählt wie rm
  cmd="${cmd##*\\}" # C:\Programme\Git\bin\git.exe zählt wie git
  cmd="${cmd%.[eE][xX][eE]}"
  local rest=("${words[@]:$((i + 1))}")
  local kind="" reader=0
  # Nur der Befehlsname ohne Rücksicht auf Großschreibung; Argumente wie --hard bleiben genau.
  shopt -s nocasematch
  case "$cmd" in
    rm | remove-item | ri) kind=rm ;;
    rd | rmdir | del | erase) kind=rd ;;
    git) kind=git ;;
    grep | egrep | fgrep) kind=grep ;;
    bash | sh | zsh | dash | ksh) kind=shell ;;
    cmd) kind=cmd ;;
    powershell | pwsh) kind=ps ;;
    invoke-expression | iex) kind=iex ;;
    select-string | sls) kind=sls ;;
    findstr) kind=findstr ;;
    get-content | gc | type) kind=gc ;;
    get-childitem | gci | dir | ls) kind=listing ;;
    where-object | where | '?' | sort-object | sort) kind=pass ;;
  esac
  case "$READERS" in *" $cmd "*) reader=1 ;; esac
  shopt -u nocasematch
  case "$kind" in
    rm) check_rm 0 ${rest[@]+"${rest[@]}"} ;;
    rd) check_rm 1 ${rest[@]+"${rest[@]}"} ;;
    git) check_git ${rest[@]+"${rest[@]}"} ;;
    grep) check_grep_recursive ${rest[@]+"${rest[@]}"} ;;
    shell) check_shell_c ${rest[@]+"${rest[@]}"} ;;
    cmd) check_cmd_c ${rest[@]+"${rest[@]}"} ;;
    ps) check_ps_c ${rest[@]+"${rest[@]}"} ;;
    iex) check_inner ${rest[@]+"${rest[@]}"} ;;
    sls) check_select_string "$from_wide" ${rest[@]+"${rest[@]}"} ;;
    findstr) check_findstr ${rest[@]+"${rest[@]}"} ;;
    gc) check_get_content "$from_wide" ${rest[@]+"${rest[@]}"} ;;
    listing) check_listing ${rest[@]+"${rest[@]}"}; PREV_WIDE="$LISTING_WIDE" ;;
    pass) PREV_WIDE="$from_wide" ;; # Where-Object und Sort-Object reichen die Liste weiter
  esac
  local a env_hit=0
  if [ "$reader" = 1 ]; then
    local skip_next=0
    for a in ${rest[@]+"${rest[@]}"}; do
      if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
      case "$a" in
        --exclude | --exclude-dir | --exclude-from) skip_next=1; continue ;;
        '>' | '>>' | [0-9]'>' | [0-9]'>>') skip_next=1; continue ;; # Ziel einer Umleitung wird geschrieben
        '>'* | [0-9]'>'*) continue ;;
        --exclude=* | --exclude-dir=* | --exclude-from=*) continue ;;
        --*=*) is_env_file "${a#*=}" && env_hit=1; continue ;; # --file=.env
        -*:?*) is_env_file "${a#*:}" && env_hit=1; continue ;; # -Path:.env
        -*) continue ;;
      esac
      is_env_file "$a" && env_hit=1
    done
  fi
  check_env_read "${words[@]}" && env_hit=1
  [ "$env_hit" = 0 ] || block "$ENV_REASON"
  return 0
}

PIPED=0
PREV_WIDE=0
json_decode "$(json_raw tool_name)"
tool="$DECODED"
case "$tool" in
  Read)
    field file_path
    is_env_file "$DECODED" &&
      block ".env-Dateien enthalten Schlüssel und bleiben ungelesen. Die Namen der Variablen stehen in .env.example."
    ;;
  Grep)
    field path
    is_env_file "$DECODED" &&
      block ".env-Dateien enthalten Schlüssel und werden nicht durchsucht. Die Namen der Variablen stehen in .env.example."
    field glob
    is_env_glob "$DECODED" &&
      block ".env-Dateien enthalten Schlüssel und werden nicht durchsucht. Die Namen der Variablen stehen in .env.example."
    ;;
  Bash | PowerShell)
    field command
    check_string "$DECODED"
    ;;
esac
exit 0
