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

# --- Meldung und Robustheit ---
run Bash command 'git reset --hard'
grep -q "git stash" "$WORK/err" && ok || bad "Begründung fehlt auf stderr"
printf 'kein json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok || bad "Kaputtes JSON muss durchgehen"
printf '' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok || bad "Leere Eingabe muss durchgehen"
run Bash command ''; [ $? = 0 ] && ok || bad "Leerer Befehl muss durchgehen"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
