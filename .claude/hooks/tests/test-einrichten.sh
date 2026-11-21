#!/usr/bin/env bash
# Tests für einrichten.sh: Die Geschichte der Vorlage wird nur gelöscht, wenn es
# weder eigene Commits noch ungesicherte Änderungen gibt.
# Lauf: bash .claude/hooks/tests/test-einrichten.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=tester.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=tester.invalid
export EINRICHTEN_SKIP_HOOKTESTS=1

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

# Kleine Vorlage mit Remote, dessen Name "OM-Claude-Code-Boilerplate" enthält.
SRC="$WORK/quelle"
mkdir -p "$SRC"
cp "$ROOT/einrichten.sh" "$ROOT/.env.example" "$ROOT/.gitignore" "$ROOT/.gitattributes" "$SRC/"
git -C "$SRC" init -q -b main 2>/dev/null || { git -C "$SRC" init -q && git -C "$SRC" checkout -q -b main; }
git -C "$SRC" add -A && git -C "$SRC" commit -q -m "vorlage"
git init -q --bare "$WORK/OM-Claude-Code-Boilerplate.git"
git -C "$SRC" remote add origin "$WORK/OM-Claude-Code-Boilerplate.git"
git -C "$SRC" push -q origin main 2>/dev/null || git -C "$SRC" push -q origin HEAD:main

klon() { git clone -q "$WORK/OM-Claude-Code-Boilerplate.git" "$WORK/$1" 2>/dev/null; }
lauf() { (cd "$WORK/$1" && bash einrichten.sh >"$WORK/$1.out" 2>&1); }
hat_remote() { [ -n "$(git -C "$WORK/$1" remote)" ]; }

# 1. Unverändert: Geschichte der Vorlage wird entfernt.
klon sauber; lauf sauber
hat_remote sauber && bad "sauberer Klon: Verweis auf die Vorlage muss weg" || ok
[ "$(git -C "$WORK/sauber" rev-list --count HEAD)" = 1 ] && ok || bad "sauberer Klon: genau ein eigener Commit"

# 2. Eigener Commit: nichts löschen.
klon commit
echo "meins" > "$WORK/commit/notiz.txt"
git -C "$WORK/commit" add -A && git -C "$WORK/commit" commit -q -m "eigene Arbeit"
lauf commit
hat_remote commit && ok || bad "eigener Commit: Geschichte darf nicht gelöscht werden"
git -C "$WORK/commit" log --format=%s | grep -q "eigene Arbeit" && ok || bad "eigener Commit: Commit muss erhalten bleiben"
grep -q "nichts gelöscht" "$WORK/commit.out" && ok || bad "eigener Commit: Erklärung fehlt"

# 3. Ungesicherte Änderung an einer Datei: nichts löschen.
klon geaendert
echo "# geändert" >> "$WORK/geaendert/.env.example"
lauf geaendert
hat_remote geaendert && ok || bad "Änderung: Geschichte darf nicht gelöscht werden"
grep -q "geändert" "$WORK/geaendert/.env.example" && ok || bad "Änderung: Datei muss erhalten bleiben"

# 4. Neue, nicht erfasste Datei: nichts löschen.
klon neu
echo "x" > "$WORK/neu/eigene-datei.txt"
lauf neu
hat_remote neu && [ -f "$WORK/neu/eigene-datei.txt" ] && ok || bad "neue Datei: nichts löschen"

# 5. Schon eigene Geschichte ohne Vorlagen-Remote bleibt, wie bisher.
mkdir "$WORK/eigen" && cp "$ROOT/einrichten.sh" "$ROOT/.env.example" "$ROOT/.gitignore" "$WORK/eigen/"
git -C "$WORK/eigen" init -q && git -C "$WORK/eigen" add -A && git -C "$WORK/eigen" commit -q -m eigen
lauf eigen
[ "$(git -C "$WORK/eigen" log --format=%s | head -1)" = "eigen" ] && ok || bad "eigene Geschichte bleibt"

# 6. Version von Claude Code: ab 2.1.324 gilt der feste Stand der Skills von Matt Pocock.
# Ein falsches `claude` im PATH liefert die Versionszeile; ohne `claude` (Desktop-App) kommt
# kein Hinweis. Das Skript darf in keinem Fall abbrechen.
claude_lauf() { # claude_lauf <name> <ausgabe oder "-" für keinen claude> [fehler]
  local d="$WORK/cl-$1" bin="$WORK/bin-$1"
  mkdir -p "$d" "$bin"
  cp "$ROOT/einrichten.sh" "$ROOT/.env.example" "$ROOT/.gitignore" "$d/"
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" commit -q -m eigen
  if [ "$2" != "-" ]; then
    printf '#!/bin/sh\n[ -n "%s" ] && echo "%s"\nexit %s\n' "$2" "$2" "${3:-0}" > "$bin/claude"
    chmod +x "$bin/claude"
  fi
  (cd "$d" && PATH="$bin:$PATH" bash einrichten.sh >"$WORK/cl-$1.out" 2>&1)
  CL_RC=$?
}
claude_lauf alt "2.1.300 (Claude Code)"
[ "$CL_RC" = 0 ] && grep -q "claude update" "$WORK/cl-alt.out" && grep -q "2.1.300" "$WORK/cl-alt.out" && grep -q "grilling" "$WORK/cl-alt.out" \
  && ok || bad "zu alte Version: Warnung mit claude update, Version und grilling fehlt"
grep -q "Fertig" "$WORK/cl-alt.out" && ok || bad "zu alte Version: Skript muss bis zum Ende laufen"
claude_lauf knapp "2.1.323 (Claude Code)"
grep -q "claude update" "$WORK/cl-knapp.out" && ok || bad "2.1.323 ist zu alt"
claude_lauf genau "2.1.324 (Claude Code)"
grep -q "claude update" "$WORK/cl-genau.out" && bad "2.1.324 reicht, keine Warnung" || ok
claude_lauf neuer "2.1.1000 (Claude Code)"
grep -q "claude update" "$WORK/cl-neuer.out" && bad "2.1.1000 ist neuer als 2.1.324, keine Warnung" || ok
claude_lauf major "3.0.0 (Claude Code)"
grep -q "claude update" "$WORK/cl-major.out" && bad "3.0.0 reicht, keine Warnung" || ok
claude_lauf unlesbar "Das ist keine Version"
[ "$CL_RC" = 0 ] && grep -q "claude update" "$WORK/cl-unlesbar.out" && grep -q "nicht lesen" "$WORK/cl-unlesbar.out" \
  && ok || bad "unlesbare Version: Warnung mit claude update fehlt oder Abbruch"
claude_lauf kaputt "" 1
[ "$CL_RC" = 0 ] && grep -q "claude update" "$WORK/cl-kaputt.out" && ok || bad "claude --version scheitert: Warnung statt Abbruch"
claude_lauf keiner -
grep -q "claude update" "$WORK/cl-keiner.out" && bad "ohne claude-Befehl keine Warnung" || ok
grep -q "Fertig" "$WORK/cl-keiner.out" && ok || bad "ohne claude-Befehl: Skript muss bis zum Ende laufen"

# 6b. Wie unter Windows: Explorer entpackt ohne Ausführrechte, Git für Windows legt Repos
# mit core.filemode=false an und nutzt core.autocrlf=true. Die Skripte müssen in Git trotzdem
# ausführbar sein (sonst ist test-repo-hygiene.sh rot), und git add darf nicht warnen.
WIN="$WORK/windows"
mkdir -p "$WIN/.claude/hooks/tests"
cp "$ROOT/einrichten.sh" "$ROOT/.env.example" "$ROOT/.gitignore" "$ROOT/.gitattributes" "$WIN/"
printf 'echo hook\n' > "$WIN/.claude/hooks/x.sh"
printf 'echo test\n' > "$WIN/.claude/hooks/tests/test-x.sh"
printf '{\n  "a": 1\n}\n' > "$WIN/daten.json"
find "$WIN" -type f -exec chmod 644 {} +
(cd "$WIN" && GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.filemode GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=core.autocrlf GIT_CONFIG_VALUE_1=true bash einrichten.sh >"$WORK/windows.out" 2>&1)
modes="$(git -C "$WIN" ls-files -s -- '*.sh' | cut -d' ' -f1 | sort -u | tr '\n' ' ')"
[ "$modes" = "100755 " ] && ok || bad "Windows: .sh-Dateien müssen in Git ausführbar sein (bekommen: $modes)"
grep -q "will be replaced" "$WORK/windows.out" && bad "Windows: git add warnt über Zeilenenden" || ok
[ "$(git -C "$WIN" rev-list --count HEAD 2>/dev/null)" = 1 ] && ok || bad "Windows: erster Commit fehlt"
grep -q "\[3/5\]" "$WORK/windows.out" && grep -q "Fertig" "$WORK/windows.out" && ok || bad "Windows: Einrichtung lief nicht durch"

# 7. einrichten.ps1 (nicht ausführbar ohne PowerShell): gleiche Mindestversion und gleicher Rat.
grep -q "2.1.324" "$ROOT/einrichten.ps1" && grep -q "claude update" "$ROOT/einrichten.ps1" \
  && ok || bad "einrichten.ps1 prüft die Version von Claude Code nicht"
# Die README sagt, dass die Einrichtung die Hooks prüft: auch unter Windows, über Git Bash.
grep -q "run-all.sh" "$ROOT/einrichten.ps1" && grep -q "Git Bash" "$ROOT/einrichten.ps1" \
  && ok || bad "einrichten.ps1 startet die Hook-Tests nicht über Git Bash"
[ "$(head -c 3 "$ROOT/einrichten.ps1" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ] \
  && ok || bad "einrichten.ps1 braucht die BOM am Anfang (sonst liest Windows PowerShell 5.1 die Umlaute falsch)"
# Auch einrichten.ps1 macht die Skripte in Git ausführbar (Git für Windows tut es nicht).
grep -q -- "--chmod=+x" "$ROOT/einrichten.ps1" && ok || bad "einrichten.ps1 setzt die Ausführrechte der .sh-Dateien in Git nicht"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
