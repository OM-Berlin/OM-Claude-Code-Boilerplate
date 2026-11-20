#!/usr/bin/env bash
# Tests für format-after-edit.sh. Statt echter Formatierer liegen kleine
# Attrappen im Testordner, die nur mitschreiben, womit sie aufgerufen wurden.
# Lauf: bash .claude/hooks/tests/test-format-after-edit.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/format-after-edit.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
P="$WORK/projekt"
LOG="$WORK/aufrufe.log"
mkdir -p "$P/src" "$WORK/bin" "$WORK/fremd"
export CLAUDE_PROJECT_DIR="$P"

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

fake() { # fake <pfad> <name>: Attrappe, die ihren Namen und die Argumente protokolliert
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$2" "$LOG" > "$1"
  chmod +x "$1"
}
edit() { # edit <file_path> -> Exitcode
  : > "$LOG"
  F="$1" python3 -c 'import json,os;print(json.dumps({"session_id":"t1","tool_name":"Edit","tool_input":{"file_path":os.environ["F"]}}))' \
    | PATH="$WORK/bin:/usr/bin:/bin" bash "$HOOK"
}
called()  { grep -q "$1" "$LOG" && ok || bad "$2"; }
silent()  { [ -s "$LOG" ] && bad "$1: $(cat "$LOG")" || ok; }

touch "$P/src/app.ts" "$P/src/tool.py" "$P/src/bild.png" "$WORK/fremd/x.ts"

# Ohne Formatierer passiert nichts.
edit "$P/src/app.ts"; [ $? = 0 ] && ok || bad "ohne Formatierer Exitcode 0"
silent "ohne Formatierer kein Aufruf"

# Prettier lokal installiert.
mkdir -p "$P/node_modules/.bin"; fake "$P/node_modules/.bin/prettier" prettier
edit "$P/src/app.ts"; called "prettier --write --log-level warn $P/src/app.ts" "Prettier muss die TS-Datei formatieren"
edit "src/app.ts"; called "prettier --write --log-level warn $P/src/app.ts" "Relativer Pfad wird im Projekt aufgelöst"
edit "$P/src/bild.png"; silent "Bilder nicht formatieren"
edit "$WORK/fremd/x.ts"; silent "Dateien außerhalb des Projekts nicht anfassen"
edit "$P/src/../../fremd/x.ts"; silent "Wege mit .. nicht anfassen"
edit "$P/src/fehlt.ts"; silent "Fehlende Datei nicht formatieren"
mkdir -p "$P/node_modules/paket"; touch "$P/node_modules/paket/i.js"
edit "$P/node_modules/paket/i.js"; silent "node_modules nicht formatieren"

# Ruff nur mit Projektkonfiguration.
fake "$WORK/bin/ruff" ruff
edit "$P/src/tool.py"; silent "Ruff ohne pyproject.toml nicht aufrufen"
touch "$P/pyproject.toml"
edit "$P/src/tool.py"; called "ruff format --quiet $P/src/tool.py" "Ruff muss die Python-Datei formatieren"

# Ein Formatierer, der scheitert, stoppt Claude nicht.
printf '#!/usr/bin/env bash\nexit 1\n' > "$P/node_modules/.bin/prettier"
edit "$P/src/app.ts"; [ $? = 0 ] && ok || bad "Fehler des Formatierers muss Exitcode 0 bleiben"

# Windows-Pfade (Laufwerksbuchstabe, Backslashes) zählen als absolut. Die Tests bilden
# C:\ auf einen Ordner im Testverzeichnis ab, weil es /c/ hier nicht gibt.
export FORMAT_HOOK_DRIVE_ROOT="$WORK/laufwerke/"
mkdir -p "$WORK/laufwerke/c/proj/src" "$WORK/laufwerke/c/proj/node_modules/.bin"
touch "$WORK/laufwerke/c/proj/src/app.ts" "$WORK/laufwerke/c/proj/src/bild.png"
fake "$WORK/laufwerke/c/proj/node_modules/.bin/prettier" prettier
export CLAUDE_PROJECT_DIR='C:\proj'
edit 'C:\proj\src\app.ts'
called "prettier --write --log-level warn $WORK/laufwerke/c/proj/src/app.ts" "Windows-Pfad mit Backslashes muss formatiert werden"
edit 'C:/proj/src/app.ts'
called "prettier --write --log-level warn $WORK/laufwerke/c/proj/src/app.ts" "Windows-Pfad mit Schrägstrichen muss formatiert werden"
edit 'D:\fremd\x.ts'; silent "Anderes Laufwerk nicht anfassen"
edit 'C:\proj\src\bild.png'; silent "Bilder auch mit Windows-Pfad nicht formatieren"
unset FORMAT_HOOK_DRIVE_ROOT
export CLAUDE_PROJECT_DIR="$P"

# Kaputte Eingabe.
printf 'kein json' | bash "$HOOK"; [ $? = 0 ] && ok || bad "Kaputtes JSON muss durchgehen"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
