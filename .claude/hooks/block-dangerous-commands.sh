#!/usr/bin/env bash
# PreToolUse-Hook: Sperrt eine kleine Liste von Befehlen, die Arbeit von Tagen
# zerstören oder Schlüssel offenlegen können:
#
#   - rm -r oder rm -rf auf / oder auf den eigenen Home-Ordner (~, $HOME)
#   - git push --force (oder -f, +main) auf main oder master
#   - git reset --hard, git clean -f sowie git checkout . und git restore . (verwerfen
#     alle ungesicherten Änderungen; einzelne Dateien und Branch-Wechsel bleiben erlaubt)
#   - bash -c oder sh -c mit einem dieser Befehle im Argument
#   - Lesen von .env-Dateien (cat .env, diff, cmp, rekursives grep über den ganzen
#     Ordner ohne --exclude, Read-Werkzeug auf .env.local, Grep-Werkzeug mit
#     glob .env* und so weiter); .env.example bleibt lesbar, dort stehen nur Platzhalter
#
# So funktioniert er: Claude Code schickt vor jedem Aufruf von Bash, Read oder Grep
# ein JSON auf stdin. Passt der Befehl zur Liste, endet der Hook mit Exitcode 2.
# Dann bricht Claude Code den Aufruf ab und zeigt Claude die Meldung von stderr.
# Claude liest den Grund und sucht einen anderen Weg. Jeder andere Exitcode lässt
# den Aufruf durch.
#
# Warum ein Hook statt einer Regel: Eine Regel in CLAUDE.md befolgt Claude meistens,
# ein Hook greift jedes Mal. Er ist eine Bremse gegen Versehen, keine
# Sicherheitsgrenze: Wer will, kommt mit Umwegen (etwa einem Skript) daran vorbei.
#
# Selbst testen:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}' \
#     | bash .claude/hooks/block-dangerous-commands.sh; echo "Exitcode: $?"
# Tests: bash .claude/hooks/tests/test-block-dangerous-commands.sh
# Nur bash, sed, grep und tr; läuft auf macOS (bash 3.2) und unter Git Bash auf Windows.
set -uo pipefail
set -f # Wörter wie * nicht als Dateinamen auflösen

BLOCKED_EXIT=2
READERS=" cat less more head tail bat nl grep egrep fgrep rg sed awk source . xxd od strings base64 cut sort uniq type Get-Content diff cmp vimdiff colordiff "
PREFIXES=" sudo env command nohup time exec builtin { "

payload="$(tr '\r\n' '  ')"
project="${CLAUDE_PROJECT_DIR:-$PWD}"

block() {
  echo "Gesperrt vom Hook block-dangerous-commands.sh: $1" >&2
  exit "$BLOCKED_EXIT"
}

# Erster String-Wert zu einem JSON-Schlüssel, einfache Escapes aufgelöst.
json_string() {
  printf '%s' "$payload" |
    sed -E -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' |
    head -n 1 |
    sed -e 's/\\"/"/g' -e 's/\\n/;/g' -e 's/\\t/ /g' -e 's/\\\\/\\/g'
}

unquote() {
  local q="'" w="$1"
  w="${w//\"/}"
  printf '%s' "${w//$q/}"
}

is_env_file() {
  local base path="${1//\\//}" # Windows-Pfade: \ wird zu /
  base="$(unquote "${path##*/}")"
  case "$base" in
    *.example | *.sample | *.template | .env.example*) return 1 ;;
    .env | .env.* | *.env) return 0 ;;
    .env*) case "$base" in *[*?[]*) return 0 ;; esac ;; # Muster wie .env*
  esac
  return 1
}

is_root_or_home() {
  local t
  t="$(unquote "$1")"
  case "$t" in
    / | /\* | /. ) return 0 ;;
    '~' | '~/' | '~/*' | '$HOME' | '$HOME/' | '$HOME/*' | '${HOME}' | '${HOME}/' | '${HOME}/*') return 0 ;;
  esac
  [ -n "${HOME:-}" ] && { [ "$t" = "$HOME" ] || [ "$t" = "$HOME/" ] || [ "$t" = "$HOME/*" ]; } && return 0
  return 1
}

# Muster für das Grep-Werkzeug (Feld glob), etwa **/.env* oder *.{js,env}.
is_env_glob() {
  local base g="${1//\\//}"
  base="$(unquote "${g##*/}")"
  is_env_file "$base" && return 0
  case "$base" in *.example* | *.sample* | *.template*) return 1 ;; esac
  case "$base" in
    *[*?[{]*) case "$base" in *.env* | *"{env"* | *",env"*) return 0 ;; esac ;;
  esac
  return 1
}

# Ziel einer rekursiven Suche, das den ganzen Ordner (und damit .env-Dateien) einschließt.
is_wide_target() {
  local t
  t="$(unquote "$1")"
  is_root_or_home "$t" && return 0
  case "$t" in . | ./ | ./\* | \* | .. | ../ | ../\*) return 0 ;; esac
  [ "$t" = "$project" ] && return 0
  [ "$t" = "$project/" ] && return 0
  return 1
}

# Rekursives grep (-r, -R, --recursive) über den ganzen Ordner liest auch .env-Dateien,
# außer eine --exclude-Angabe nimmt sie aus. Einzelne Unterordner wie src bleiben frei.
check_grep_recursive() { # check_grep_recursive <args nach grep>
  local a prev="" recursive=0 positional=0 has_pattern_opt=0 wide=0
  for a in "$@"; do
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

check_rm() { # check_rm <args...>
  local recursive=0 a targets=""
  for a in "$@"; do
    case "$a" in
      --recursive) recursive=1 ;;
      --*) ;;
      -*) case "$a" in *[rR]*) recursive=1 ;; esac ;;
      *) is_root_or_home "$a" && targets="$a" ;;
    esac
  done
  [ "$recursive" = 1 ] && [ -n "$targets" ] &&
    block "rm -r auf '$targets' würde das ganze System oder den Home-Ordner löschen. Lösch nur einzelne Dateien im Projekt und frag vorher nach."
}

is_whole_tree() { # "." und Verwandte: alle Dateien im Ordner
  case "$(unquote "$1")" in . | ./ | ./\* | \* | :/ | :/.) return 0 ;; esac
  return 1
}

is_main() {
  local ref="$(unquote "${1#+}")"
  ref="${ref##*:}"
  ref="${ref#refs/heads/}"
  [ "$ref" = "main" ] || [ "$ref" = "master" ]
}

check_git() { # check_git <args nach "git">
  local dir="$project" sub="" force=0 all=0 a positional=0 skip=0 hits_main=0 has_refspec=0
  local staged=0 worktree=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) dir="$(unquote "${2:-}")"; shift 2; continue ;;
      -c) shift 2; continue ;;
      -*) shift; continue ;;
    esac
    sub="$1"; shift; break
  done
  case "$sub" in
    clean)
      for a in "$@"; do
        case "$a" in
          --force) block "git clean --force löscht ungesicherte Dateien endgültig. Nutze git clean -n für eine Vorschau und frag den Nutzer, bevor etwas gelöscht wird." ;;
          --*) ;;
          -*f*) block "git clean -f löscht ungesicherte Dateien endgültig. Nutze git clean -n für eine Vorschau und frag den Nutzer, bevor etwas gelöscht wird." ;;
        esac
      done
      ;;
    checkout | restore)
      for a in "$@"; do
        case "$a" in
          --staged) staged=1 ;;
          --worktree) worktree=1 ;;
          --*) ;;
          -*) case "$a" in *S*) staged=1 ;; esac
              case "$a" in *W*) worktree=1 ;; esac ;;
          *) is_whole_tree "$a" && all=1 ;;
        esac
      done
      # git restore --staged . nimmt Änderungen nur aus der Vormerkung, die Dateien bleiben.
      if [ "$all" = 1 ] && ! { [ "$sub" = restore ] && [ "$staged" = 1 ] && [ "$worktree" = 0 ]; }; then
        block "git $sub . verwirft alle nicht gesicherten Änderungen im Ordner. Nutze git stash, nenne einzelne Dateien oder frag den Nutzer, bevor etwas verworfen wird."
      fi
      ;;
    reset)
      for a in "$@"; do
        [ "$a" = "--hard" ] && block "git reset --hard verwirft alle nicht gesicherten Änderungen. Nutze git stash oder frag den Nutzer, bevor etwas verworfen wird."
      done
      ;;
    push)
      for a in "$@"; do
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

check_string() { # zerlegt einen Befehlstext an ; & | ( ) und Backticks und prüft jedes Stück
  local seg
  while IFS= read -r seg; do
    check_segment "$seg"
  done <<<"$(printf '%s' "$1" | tr ';&|()`' '\n\n\n\n\n\n')"
}

check_shell_c() { # check_shell_c <args nach bash/sh>: bash -c "..." prüft den Text im Argument
  local a found=0 inner=""
  for a in "$@"; do
    if [ "$found" = 1 ]; then inner="$inner $a"; continue; fi
    case "$a" in -c | -[!-]*c*) found=1 ;; esac
  done
  [ -n "$inner" ] && check_string "$(unquote "$inner")"
  return 0
}

check_segment() {
  local -a words
  read -r -a words <<<"$1"
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
  cmd="$(unquote "${words[$i]}")"
  cmd="${cmd##*/}" # /bin/rm zählt wie rm
  local rest=("${words[@]:$((i + 1))}")
  case "$cmd" in
    rm) check_rm ${rest[@]+"${rest[@]}"} ;;
    git) check_git ${rest[@]+"${rest[@]}"} ;;
    grep | egrep | fgrep) check_grep_recursive ${rest[@]+"${rest[@]}"} ;;
    bash | sh | zsh | dash | ksh) check_shell_c ${rest[@]+"${rest[@]}"} ;;
  esac
  local a env_hit=0
  case "$READERS" in
    *" $cmd "*)
      local skip_next=0
      for a in ${rest[@]+"${rest[@]}"}; do
        if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
        case "$a" in --exclude | --exclude-dir | --exclude-from) skip_next=1; continue ;; esac
        case "$a" in -*) continue ;; esac
        is_env_file "$a" && env_hit=1
      done
      ;;
  esac
  check_env_read "${words[@]}" && env_hit=1
  [ "$env_hit" = 0 ] ||
    block ".env-Dateien enthalten Schlüssel und bleiben ungelesen. Die Namen der Variablen stehen in .env.example. Braucht ein Programm einen Wert, liest es ihn selbst aus .env.local."
  return 0
}

tool="$(json_string tool_name)"
case "$tool" in
  Read)
    is_env_file "$(json_string file_path)" &&
      block ".env-Dateien enthalten Schlüssel und bleiben ungelesen. Die Namen der Variablen stehen in .env.example."
    ;;
  Grep)
    is_env_file "$(json_string path)" &&
      block ".env-Dateien enthalten Schlüssel und werden nicht durchsucht. Die Namen der Variablen stehen in .env.example."
    is_env_glob "$(json_string glob)" &&
      block ".env-Dateien enthalten Schlüssel und werden nicht durchsucht. Die Namen der Variablen stehen in .env.example."
    ;;
  Bash)
    check_string "$(json_string command)"
    ;;
esac
exit 0
