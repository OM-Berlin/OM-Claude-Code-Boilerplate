#!/usr/bin/env bash
# Tests für block-dangerous-commands.sh: JSON rein wie von Claude Code, Exitcode raus.
# Exitcode 2 heißt gesperrt, 0 heißt erlaubt.
# Lauf: bash .claude/hooks/tests/test-block-dangerous-commands.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-dangerous-commands.sh"
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
  TOOL="$1" KEY="$2" VAL="$3" python3 -c 'import json,os;print(json.dumps({"session_id":"t1","tool_name":os.environ["TOOL"],"tool_input":{os.environ["KEY"]:os.environ["VAL"],"description":"Test"}}))' \
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
run Read file_path "/home/anna/projekt/README.md"; [ $? = 0 ] && ok || bad "Read README muss erlaubt sein"
run Grep path ".env.local"; [ $? = 2 ] && ok || bad "Grep in .env.local muss gesperrt sein"
run Write file_path ".env.local"; [ $? = 0 ] && ok || bad "Andere Werkzeuge bleiben unberührt"

# --- Meldung und Robustheit ---
run Bash command 'git reset --hard'
grep -q "git stash" "$WORK/err" && ok || bad "Begründung fehlt auf stderr"
printf 'kein json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok || bad "Kaputtes JSON muss durchgehen"
printf '' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok || bad "Leere Eingabe muss durchgehen"
run Bash command ''; [ $? = 0 ] && ok || bad "Leerer Befehl muss durchgehen"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
