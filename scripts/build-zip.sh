#!/usr/bin/env bash
# Baut aus dem letzten Commit ein sauberes Startpaket für Teilnehmende:
#
#   bash scripts/build-zip.sh [zielordner]
#
# Ergebnis: <zielordner>/startpaket-claude-code.zip (Standard: dist/), darin ein
# Ordner startpaket-claude-code/. Grundlage ist `git archive`, deshalb fehlen
# automatisch .git, alles Ungetrackte (.env.local, Test-Reste, .DS_Store) und alles,
# was in .gitattributes mit export-ignore markiert ist (etwa dieses Skript).
# Das Skript bricht ab, wenn es ungesicherte Änderungen gibt, damit das ZIP genau
# einem Commit entspricht.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/dist}"
NAME="startpaket-claude-code"

cd "$ROOT"
if [ -n "$(git status --porcelain)" ]; then
  echo "Abbruch: Es gibt ungesicherte Änderungen. Erst committen, dann bauen." >&2
  git status --short >&2
  exit 1
fi

echo "Hook-Tests laufen ..."
bash .claude/hooks/tests/run-all.sh >/dev/null || {
  echo "Abbruch: Hook-Tests sind rot. Details: bash .claude/hooks/tests/run-all.sh" >&2
  exit 1
}

mkdir -p "$OUT_DIR"
OUT="$(cd "$OUT_DIR" && pwd)/$NAME.zip"
rm -f "$OUT"
git archive --format=zip --prefix="$NAME/" -o "$OUT" HEAD

commit="$(git rev-parse --short HEAD)"
count="$(unzip -Z1 "$OUT" | grep -vc '/$')"
echo "Fertig: $OUT"
echo "Stand: Commit $commit, $count Dateien."
