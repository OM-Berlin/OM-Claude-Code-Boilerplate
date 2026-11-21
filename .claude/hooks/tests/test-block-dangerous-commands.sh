#!/usr/bin/env bash
# Tests für block-dangerous-commands.sh: JSON rein wie von Claude Code, Exitcode raus.
# Exitcode 2 heißt gesperrt, 0 heißt erlaubt.
# Lauf: bash .claude/hooks/tests/test-block-dangerous-commands.sh
set -uo pipefail
# Der Schalter aus der eigenen Shell darf die Tests nicht abschalten; geprüft wird er unten.
unset OM_SCHUTZ_HOOK

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-dangerous-commands.sh"

# Die Tests bauen ihr JSON mit Python. Gesucht wird wie in den Hooks (find-python.sh).
. "$(dirname "$HOOK")/find-python.sh"
find_python || { echo "Python 3 fehlt, Test übersprungen (gesucht: python3, python, py -3)"; exit 0; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Zwei Git-Repos für den Fall "force push ohne Branch-Angabe".
for b in main feature; do
  mkdir -p "$WORK/$b"
  git -C "$WORK/$b" init -q -b "$b" 2>/dev/null || { git -C "$WORK/$b" init -q && git -C "$WORK/$b" checkout -q -b "$b"; }
done
export CLAUDE_PROJECT_DIR="$WORK/feature"

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

run() { # run <tool> <feld> <wert> -> Exitcode
  TOOL="$1" KEY="$2" VAL="$3" $PY_CMD -c 'import json,os;print(json.dumps({"session_id":"t1","tool_name":os.environ["TOOL"],"tool_input":{os.environ["KEY"]:os.environ["VAL"],"description":"Test"}}))' \
    | bash "$HOOK" >/dev/null 2>"$WORK/err"
}
blocked() { run Bash command "$1"; rc=$?; [ "$rc" = 2 ] && ok || bad "muss gesperrt sein (rc=$rc): $1"; }
allowed() { run Bash command "$1"; rc=$?; [ "$rc" = 0 ] && ok || bad "muss erlaubt sein (rc=$rc): $1"; }

# --- rm auf / oder ~ ---
blocked 'rm -rf /'
blocked 'rm -rf /*'
blocked 'rm -rf ~'
blocked 'rm -rf ~/'
blocked 'rm -fr ~/*'
blocked 'rm -r -f $HOME'
blocked 'rm -rf "$HOME"'
blocked 'rm -rf ${HOME}/'
blocked "rm -rf $HOME"
blocked 'rm --recursive --force /'
blocked 'sudo rm -rf /'
blocked '/bin/rm -Rf ~'
blocked 'cd /tmp && rm -rf ~'
blocked 'echo ok; rm -rf /'
blocked 'ls | rm -rf ~'
blocked '{ rm -rf /; }'
allowed 'rm -rf build'
allowed 'rm -rf ./dist node_modules'
allowed 'rm -rf ~/projekt/tmp'
allowed 'rm datei.txt'
allowed 'rm ~'

# --- git push --force auf main ---
blocked 'git push --force origin main'
blocked 'git push -f origin master'
blocked 'git push origin main --force'
blocked 'git push --force-with-lease origin main'
blocked 'git push origin +main'
blocked 'git push origin HEAD:main -f'
blocked 'git push -uf origin refs/heads/main'
blocked 'git push --force --all'
blocked "git -C $WORK/main push --force"
blocked "git -C $WORK/main push -f origin HEAD"
allowed 'git push origin main'
allowed 'git push'
allowed 'git push --force origin feature'
allowed 'git push --force'
allowed "git -C $WORK/main push"
allowed 'git push -o ci.skip origin feature'

# --- git reset --hard ---
blocked 'git reset --hard'
blocked 'git reset --hard HEAD~3'
blocked 'git -C /tmp/x reset --hard origin/main'
blocked 'git stash && git reset --hard'
allowed 'git reset HEAD datei.txt'
allowed 'git reset --soft HEAD~1'
allowed 'git status'

# --- .env lesen ---
blocked 'cat .env'
blocked 'cat .env.local'
blocked 'less ./config/.env.production'
blocked 'grep KEY .env.local'
blocked 'source .env'
blocked '. .env.local'
blocked 'head -n 5 "/home/anna/projekt/.env"'
blocked 'python3 app.py < .env'
blocked 'echo $(cat .env.local)'
blocked 'cat prod.env'
allowed 'cat .env.example'
allowed 'cp .env.example .env.local'
allowed 'git check-ignore .env.local'
allowed 'ls -la'
allowed 'cat README.md'
allowed 'grep -rn TODO projects'

run Read file_path "/home/anna/projekt/.env.local"; [ $? = 2 ] && ok || bad "Read .env.local muss gesperrt sein"
run Read file_path "/home/anna/projekt/.env"; [ $? = 2 ] && ok || bad "Read .env muss gesperrt sein"
run Read file_path "/home/anna/projekt/.env.example"; [ $? = 0 ] && ok || bad "Read .env.example muss erlaubt sein"
run Read file_path 'C:\Users\max\proj\.env.local'; [ $? = 2 ] && ok || bad "Read mit Windows-Pfad auf .env.local muss gesperrt sein"
run Read file_path 'C:\Users\max\proj\.env'; [ $? = 2 ] && ok || bad "Read mit Windows-Pfad auf .env muss gesperrt sein"
run Read file_path 'C:\Users\max\proj\.env.example'; [ $? = 0 ] && ok || bad "Read mit Windows-Pfad auf .env.example muss erlaubt sein"
run Grep path 'C:\Users\max\proj\.env.local'; [ $? = 2 ] && ok || bad "Grep mit Windows-Pfad muss gesperrt sein"
run Read file_path "/home/anna/projekt/README.md"; [ $? = 0 ] && ok || bad "Read README muss erlaubt sein"
run Grep path ".env.local"; [ $? = 2 ] && ok || bad "Grep in .env.local muss gesperrt sein"
run Write file_path ".env.local"; [ $? = 0 ] && ok || bad "Andere Werkzeuge bleiben unberührt"

# --- .env per Muster lesen ---
blocked 'cat .env*'
blocked 'cat config/.env.*'
blocked 'head -n 3 .env?'
blocked 'cat .env[.]local'
allowed 'cat .env.example'
allowed 'cat .env.example*'
allowed 'cat .envrc.md'

# --- .env über Vergleichsprogramme, rekursive Suche und das Grep-Werkzeug ---
blocked 'diff .env.example .env.local'
blocked 'diff -u .env.local .env.example'
blocked 'cmp .env.local /tmp/x'
blocked 'vimdiff .env.example .env.local'
blocked 'grep -rn API_KEY .'
blocked 'grep -R API_KEY .'
blocked 'grep -r API_KEY'
blocked 'grep -rni key ./'
blocked 'grep --recursive KEY .'
blocked 'grep -rn KEY *'
blocked 'egrep -r KEY ..'
blocked "grep -rn KEY $WORK/feature"
blocked 'grep -rn KEY "."'
allowed 'diff a.txt b.txt'
allowed 'diff .env.example .env.sample'
allowed 'cmp a.bin b.bin'
allowed 'grep -rn API_KEY . --exclude=.env*'
allowed "grep -rn API_KEY --exclude='.env*' ."
allowed 'grep -rn KEY . --exclude .env.local'
allowed 'grep -rn TODO src'
allowed 'grep -rn TODO ./src'
allowed 'grep -n KEY README.md'
allowed 'grep KEY file.txt'
allowed 'ls | grep foo'
run Grep glob '**/.env*'; [ $? = 2 ] && ok || bad "Grep mit glob **/.env* muss gesperrt sein"
run Grep glob '.env.*'; [ $? = 2 ] && ok || bad "Grep mit glob .env.* muss gesperrt sein"
run Grep glob '*.env'; [ $? = 2 ] && ok || bad "Grep mit glob *.env muss gesperrt sein"
run Grep glob '*.{js,env}'; [ $? = 2 ] && ok || bad "Grep mit glob *.{js,env} muss gesperrt sein"
run Grep glob '*.ts'; [ $? = 0 ] && ok || bad "Grep mit glob *.ts muss erlaubt sein"
run Grep glob '**/*.md'; [ $? = 0 ] && ok || bad "Grep mit glob **/*.md muss erlaubt sein"
run Grep glob '.env.example'; [ $? = 0 ] && ok || bad "Grep mit glob .env.example muss erlaubt sein"
run Grep glob '*environment*.md'; [ $? = 0 ] && ok || bad "Grep mit glob *environment*.md muss erlaubt sein"

# --- alle Änderungen im Arbeitsordner verwerfen ---
blocked 'git checkout -- .'
blocked 'git checkout .'
blocked 'git checkout HEAD -- .'
blocked 'git checkout -f -- .'
blocked 'git checkout main .'
blocked 'git -C /tmp/x checkout .'
blocked 'git restore .'
blocked 'git restore -- .'
blocked 'git restore --worktree .'
blocked 'git restore --staged --worktree .'
blocked 'git restore -SW .'
blocked 'git restore --source=HEAD .'
blocked 'git status && git checkout .'
blocked 'git checkout -- "."'
allowed 'git restore datei.txt'
allowed 'git restore src/app.js README.md'
allowed 'git restore --staged datei.txt'
allowed 'git restore --staged .'
allowed 'git restore -S .'
allowed 'git checkout main'
allowed 'git checkout -b neuer-zweig'
allowed 'git checkout feature/x'
allowed 'git checkout -- datei.txt'
allowed 'git checkout main -- datei.txt'
allowed 'git checkout -'
allowed 'git checkout --orphan sauber'
allowed 'git switch main'
run Bash command 'git checkout .'
grep -q "git stash" "$WORK/err" && ok || bad "Begründung für git checkout . fehlt auf stderr"

# --- git clean -f ---
blocked 'git clean -f'
blocked 'git clean -fd'
blocked 'git clean -xdf'
blocked 'git clean -d --force'
blocked 'git -C /tmp/x clean -fdx'
allowed 'git clean -n'
allowed 'git clean -nd'
allowed 'git clean --dry-run'

# --- bash -c / sh -c ---
blocked 'bash -c "git reset --hard"'
blocked "sh -c 'rm -rf ~'"
blocked 'bash -lc "cat .env.local"'
blocked "bash -c 'cd x && git push --force origin main'"
blocked "sh -c 'git clean -fd'"
blocked "bash -c \"bash -c 'rm -rf /'\""
allowed 'bash -c "echo hallo"'
allowed 'bash -c "rm -rf node_modules"'
allowed 'bash einrichten.sh'
allowed 'sh -c "git status"'

# --- Windows: Laufwerk, Benutzerordner und das PowerShell-Werkzeug von Claude Code ---
blocked 'rm -rf C:\'
blocked 'rm -rf C:/'
blocked 'rm -rf /c'
blocked 'rm -rf /c/'
blocked 'rm -rf $USERPROFILE'
blocked 'rm -rf "$env:USERPROFILE"'
blocked 'rm -rf %USERPROFILE%'
USERPROFILE='C:\Users\Test' run Bash command 'rm -rf C:\Users\Test'; rc=$?
[ "$rc" = 2 ] && ok || bad "rm -rf auf den Windows-Benutzerordner muss gesperrt sein (rc=$rc)"
USERPROFILE='C:\Users\Test' run Bash command 'rm -rf /c/Users/Test/'; rc=$?
[ "$rc" = 2 ] && ok || bad "rm -rf auf /c/Users/Test/ muss gesperrt sein (rc=$rc)"
allowed 'rm -rf C:\Users\Test\proj\node_modules'
allowed 'rm -rf /c/Users/Test/proj/dist'
ps_blocked() { run PowerShell command "$1"; rc=$?; [ "$rc" = 2 ] && ok || bad "PowerShell muss gesperrt sein (rc=$rc): $1"; }
ps_allowed() { run PowerShell command "$1"; rc=$?; [ "$rc" = 0 ] && ok || bad "PowerShell muss erlaubt sein (rc=$rc): $1"; }
ps_blocked 'git reset --hard'
ps_blocked 'git push --force origin main'
ps_blocked 'Get-Content .env.local'
ps_blocked 'gc .env'
ps_blocked 'type .env.local'
ps_blocked 'Select-String KEY .env.local'
ps_blocked 'Remove-Item -Recurse -Force ~'
ps_blocked 'remove-item -recurse $HOME'
ps_blocked 'Remove-Item -Recurse -Force $env:USERPROFILE'
ps_blocked 'rd -r C:\'
ps_allowed 'Get-ChildItem'
ps_allowed 'Get-Content README.md'
ps_allowed 'Remove-Item -Recurse -Force node_modules'
ps_allowed 'git status'

# Eingehängt für PowerShell: Ohne Git Bash oder mit dem PowerShell-Werkzeug ruft Claude Code
# unter Windows PowerShell statt Bash; der matcher muss beide Werkzeuge nennen.
SETTINGS="$(dirname "$(dirname "$HOOK")")/settings.json"
if [ -f "$SETTINGS" ]; then
  $PY_CMD - "$SETTINGS" <<'PY' && ok || bad "settings.json: block-dangerous-commands.sh muss für Bash und PowerShell eingehängt sein"
import json, re, sys
groups = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"]
hits = [g.get("matcher", "") for g in groups
        if any("block-dangerous-commands.sh" in h.get("command", "") for h in g["hooks"])]
sys.exit(0 if hits and all(re.fullmatch(m, t) for m in hits for t in ("Bash", "PowerShell", "Read", "Grep")) else 1)
PY
fi

# --- erlaubt bleiben muss weiterhin ---
allowed 'rm -rf node_modules'
allowed 'git push --force-with-lease origin feature'
allowed 'cat .env.example'

# --- Schalter OM_SCHUTZ_HOOK: nur "aus" schaltet ab, Standard ist an ---
OM_SCHUTZ_HOOK=aus run Bash command 'git reset --hard'; rc=$?
[ "$rc" = 0 ] && ok || bad "OM_SCHUTZ_HOOK=aus lässt git reset --hard durch (rc=$rc)"
OM_SCHUTZ_HOOK=aus run Read file_path '.env.local'; rc=$?
[ "$rc" = 0 ] && ok || bad "OM_SCHUTZ_HOOK=aus lässt Read auf .env.local durch (rc=$rc)"
[ ! -s "$WORK/err" ] && ok || bad "OM_SCHUTZ_HOOK=aus bleibt still"
OM_SCHUTZ_HOOK=an run Bash command 'git reset --hard'; rc=$?
[ "$rc" = 2 ] && ok || bad "OM_SCHUTZ_HOOK=an sperrt (rc=$rc)"
OM_SCHUTZ_HOOK=AUS run Bash command 'git reset --hard'; rc=$?
[ "$rc" = 2 ] && ok || bad "anderer Wert als aus sperrt weiter (rc=$rc)"
OM_SCHUTZ_HOOK= run Bash command 'git reset --hard'; rc=$?
[ "$rc" = 2 ] && ok || bad "leerer Wert sperrt weiter (rc=$rc)"

# --- HOOK_AUSGABE=json (Codex unter Windows): Sperre als JSON auf stdout, Exitcode 0 ---
json_block() { # json_block <befehl>: gültiges JSON mit deny und Grund, Exitcode 0
  local out rc
  out="$(TOOL=Bash KEY=command VAL="$1" $PY_CMD -c 'import json,os;print(json.dumps({"tool_name":os.environ["TOOL"],"tool_input":{os.environ["KEY"]:os.environ["VAL"]}}))' \
    | HOOK_AUSGABE=json bash "$HOOK" 2>/dev/null)"; rc=$?
  printf '%s' "$out" | $PY_CMD -c 'import json,sys; o=json.load(sys.stdin)["hookSpecificOutput"]; sys.exit(0 if o["permissionDecision"] == "deny" and o["permissionDecisionReason"].startswith("Gesperrt") else 1)' \
    && [ "$rc" = 0 ] && ok || bad "HOOK_AUSGABE=json muss deny als gültiges JSON melden (rc=$rc): $1" "$out"
}
json_block 'git reset --hard'
json_block 'rm -rf "~/"'
json_block 'rm -rf C:\'
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | HOOK_AUSGABE=json bash "$HOOK")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok || bad "HOOK_AUSGABE=json: erlaubter Befehl ohne Ausgabe (rc=$rc)" "$out"

# --- Windows-Pfade, cmd, PowerShell (Review vom 21.11.2026) ---
# Rückwärtsstriche entstehen erst zur Laufzeit aus #, damit keine Werkzeugschicht
# Folgen wie Backslash-n, Backslash-t oder Backslash-u schon vorher auflöst.
B="$(printf '\134')"
NL="$(printf '\012x')"; NL="${NL%x}"
WIN_HOME="C:${B}Users${B}nina"
wrun() { W="${2//#/$B}"; USERPROFILE="$WIN_HOME" run "$1" command "$W"; }
wblocked() { wrun PowerShell "$1"; rc=$?; [ "$rc" = 2 ] && ok || bad "Windows muss gesperrt sein (rc=$rc): $W"; }
wallowed() { wrun PowerShell "$1"; rc=$?; [ "$rc" = 0 ] && ok || bad "Windows muss erlaubt sein (rc=$rc): $W"; }
# H1: Backslash plus n oder t im Pfad bleibt Backslash plus Buchstabe.
wblocked 'Remove-Item -Recurse -Force C:#Users#nina'
wblocked 'Remove-Item -Recurse -Force C:#USERS#NINA#'
wblocked 'Get-Content C:#Projekte#neu#.env'
wblocked 'git -C C:#new#app reset --hard'
wblocked 'git -C C:#temp#app clean -fd'
wrun Bash 'git -C C:#new#app reset --hard'; [ $? = 2 ] && ok || bad "Bash-Werkzeug muss gesperrt sein: $W"
allowed 'git -C'
# H2: cmd-Schreibweise und cmd /c, powershell -Command
wblocked 'cmd /c rd /s /q %USERPROFILE%'
wblocked 'cmd /c "rmdir /s /q C:#Users#nina"'
wblocked 'del /s /q %USERPROFILE%#*'
wblocked 'erase /s /q %USERPROFILE%#*'
wblocked 'rd /s /q C:#'
wblocked 'rd /S /Q C:#Users#nina'
wblocked 'cmd /c "git reset --hard"'
wblocked 'cmd.exe /C "git status & git reset --hard"'
wblocked 'cmd /k git clean -fd'
wblocked 'pwsh -c "git reset --hard"'
wblocked 'powershell -Command "Remove-Item -Recurse -Force ~"'
wblocked 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command git reset --hard'
wblocked 'Invoke-Expression "git reset --hard"'
wblocked 'pwsh -EncodedCommand ZwBpAHQAIAByAGUAcwBlAHQA'
grep -q "EncodedCommand" "$WORK/err" && ok || bad "Begründung für -EncodedCommand fehlt auf stderr"
wblocked 'powershell -enc ZwBpAHQA'
blocked 'bash -c "git status && git reset --hard"'
blocked "git reset '--hard'"
blocked 'rm "-rf" ~'
# M3: Home in allen Schreibweisen, Großschreibung egal
wblocked 'Remove-Item -Recurse -Force $Env:USERPROFILE'
wblocked 'Remove-Item -Recurse ${env:USERPROFILE}'
wblocked 'Remove-Item -Recurse -Force $home'
wblocked 'Remove-Item -Recurse -Force $env:USERPROFILE#*'
wblocked 'Remove-Item -Recurse -Force $env:USERPROFILE/*'
wblocked 'rd /s /q %USERPROFILE%#*'
wblocked 'rd /s /q %userprofile%'
wblocked 'rm -rf $HOME/*'
# M4: .env über PowerShell und cmd
wblocked 'Get-ChildItem -Recurse | Select-String API_KEY'
wblocked 'gci -r | sls KEY'
wblocked 'Get-ChildItem | Get-Content'
wblocked 'Select-String -Path * -Pattern KEY'
wblocked 'Select-String KEY *.*'
wblocked 'findstr API .env'
wblocked 'findstr /s KEY *'
wblocked 'findstr /g:.env README.md'
wblocked 'type .env'
wblocked 'gc .env.local'
wblocked 'cat .#.env'
wblocked 'cat .ENV'
wblocked 'Get-Content .Env.Local'
wblocked 'Get-Content -Path:.env'
wblocked 'cmd /c type .env'
# Gewöhnliche Befehle mit Windows-Pfaden bleiben erlaubt.
wallowed 'cd C:#Users#nina#projekt'
wallowed 'Copy-Item C:#temp#a.txt C:#temp#b.txt'
wallowed 'git -C C:#new#app status'
wallowed 'Remove-Item C:#temp#build#out.txt'
wallowed 'rm -r -fo C:#temp#build'
wallowed 'Remove-Item -Recurse -Force C:#Users#david#node_modules'
wallowed 'Remove-Item -Recurse -Force C:#Users#nina#projekt#node_modules'
wallowed 'Remove-Item -Recurse ~#tmp'
wallowed 'type README.md'
wallowed 'findstr TODO src#*.js'
wallowed 'findstr /s TODO *.js'
wallowed 'Get-Content .env.example'
wallowed 'cat .ENV.EXAMPLE'
wallowed 'del notes.txt'
wallowed 'rd /s /q build'
wallowed 'cmd /c dir'
wallowed 'cmd /c "git status"'
wallowed 'pwsh -c "git status"'
wallowed 'powershell -ExecutionPolicy Bypass -File build.ps1'
wallowed 'Get-ChildItem -Recurse src | Select-String TODO'
wallowed 'Get-ChildItem -Recurse -Exclude .env* | Select-String KEY'
wallowed 'Get-ChildItem -Recurse -Filter *.ts | Select-String TODO'
wallowed 'Get-ChildItem -Recurse | Select-Object Name'
wallowed 'Select-String TODO README.md'
wallowed 'Remove-Item -Recurse $homepath'
wallowed 'type nul > .env.local'
wblocked 'type .env > kopie.txt'

# JSON-Escapes werden in einem Durchgang aufgelöst. Das JSON entsteht hier als Rohtext.
raw() { printf '%s' "$1" | USERPROFILE="$WIN_HOME" bash "$HOOK" >/dev/null 2>"$WORK/err"; }
raw '{"tool_name":"Bash","tool_input":{"command":"git reset '"${B}"'u002d-hard"}}'; [ $? = 2 ] && ok || bad "U+002d im JSON wird zu - und sperrt git reset --hard"
raw '{"tool_name":"Bash","tool_input":{"command":"echo ok'"${B}"'ngit reset --hard"}}'; [ $? = 2 ] && ok || bad "JSON-Zeilenumbruch trennt Befehle"
raw '{"tool_name":"Bash","tool_input":{"command":"echo '"${B}${B}"'u0026 ok"}}'; [ $? = 0 ] && ok || bad "doppelter Backslash vor u0026 ist kein &"
raw '{"tool_name":"PowerShell","tool_input":{"command":"rm -r -fo C:'"${B}${B}"'temp'"${B}${B}"'build"}}'; [ $? = 0 ] && ok || bad "Rohtext: C:\\temp\\build bleibt erlaubt"
raw '{"tool_name":"Bash","tool_input":{"command":"echo '"${B}"'u0000"}}'; [ $? = 2 ] && ok || bad "U+0000 ist nicht prüfbar und wird gesperrt"
raw '{"tool_name":"Bash","tool_input":{"command":"echo caf'"${B}"'u00e9"}}'; [ $? = 0 ] && ok || bad "U+00e9 wird zu é und bleibt erlaubt"
run Bash command "echo ok${NL}git reset --hard"; [ $? = 2 ] && ok || bad "echter Zeilenumbruch trennt Befehle"

# L6: Ungültiges UTF-8 darf die Prüfung nicht aushebeln, auch nicht in einer UTF-8-Umgebung.
printf '{"tool_name":"Bash","tool_input":{"command":"git reset --hard \377"}}' | LC_ALL=en_US.UTF-8 bash "$HOOK" >/dev/null 2>&1
[ $? = 2 ] && ok || bad "ungültiges UTF-8: git reset --hard bleibt gesperrt"
printf '{"tool_name":"Bash","tool_input":{"command":"cat \377 .env.local"}}' | LC_ALL=en_US.UTF-8 bash "$HOOK" >/dev/null 2>&1
[ $? = 2 ] && ok || bad "ungültiges UTF-8: cat .env.local bleibt gesperrt"

# L5: Tempo. Manche Programme geben einem Hook nur 10 Sekunden; danach läuft der Befehl
# ungeprüft. Unter Git Bash kostet jeder Extra-Prozess ein Vielfaches von macOS, deshalb
# darf der Hook pro Argument keinen Prozess starten. Grenze: 300 Argumente in 2 Sekunden
# auf einem aktuellen Mac.
big="Remove-Item"
i=0
while [ "$i" -lt 300 ]; do big="$big C:#temp#build#out$i.txt"; i=$((i + 1)); done
t0="$($PY_CMD -c 'import time; print(time.time())')"
wrun PowerShell "$big"; rc=$?
t1="$($PY_CMD -c 'import time; print(time.time())')"
[ "$rc" = 0 ] && ok || bad "300 Argumente: erlaubt erwartet (rc=$rc)"
$PY_CMD -c "import sys; sys.exit(0 if $t1 - $t0 < 2.0 else 1)" && ok ||
  bad "300 Argumente dauern länger als 2 Sekunden: $($PY_CMD -c "print(round($t1 - $t0, 2))") s"

# --- Meldung und Robustheit ---
run Bash command 'git reset --hard'
grep -q "git stash" "$WORK/err" && ok || bad "Begründung fehlt auf stderr"
printf 'kein json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok || bad "Kaputtes JSON muss durchgehen"
printf '' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok || bad "Leere Eingabe muss durchgehen"
run Bash command ''; [ $? = 0 ] && ok || bad "Leerer Befehl muss durchgehen"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
