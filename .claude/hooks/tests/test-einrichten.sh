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
cp "$ROOT/einrichten.sh" "$ROOT/.env.example" "$ROOT/.gitignore" "$SRC/"
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

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
