#!/usr/bin/env bash
# Startet alle Hook-Tests nacheinander und prüft, dass jeder Skill, der sowohl in
# .claude/skills/ (Claude Code) als auch in .agents/skills/ (Codex, Antigravity, Pi)
# liegt, in beiden Kopien gleich ist. Liegt ein Skill nur an einer Stelle, gibt es
# nichts zu vergleichen.
#
# Übersprungen: Gibt eine Testdatei "übersprungen" aus (etwa weil Python, Node oder eine
# Vergleichsquelle fehlt), lief sie nicht vollständig. Die Zusammenfassung nennt sie dann
# mit Namen, und die letzte Zeile zählt sie. "Alle Tests grün." steht nur, wenn alles lief.
# Lauf: bash .claude/hooks/tests/run-all.sh
# Tests: bash .claude/hooks/tests/test-run-all.sh
# bash 3.2 kompatibel (macOS).
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS/../../.." && pwd)"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
failed=0
skipped=0
skipped_names=""

for t in "$TESTS"/test-*.sh; do
  [ -f "$t" ] || continue
  name="$(basename "$t")"
  echo "── $name"
  bash "$t" 2>&1 | tee "$LOG"
  [ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
  if grep -q 'übersprungen' "$LOG"; then
    skipped=$((skipped + 1))
    skipped_names="${skipped_names:+$skipped_names, }$name"
  fi
done

echo "── Skill-Kopien"
pairs=0
for a in "$ROOT"/.agents/skills/*/SKILL.md; do
  [ -f "$a" ] || continue
  name="$(basename "$(dirname "$a")")"
  c="$ROOT/.claude/skills/$name/SKILL.md"
  [ -f "$c" ] || continue
  pairs=$((pairs + 1))
  if ! cmp -s "$c" "$a"; then
    echo "FAIL: .agents/skills/$name/SKILL.md weicht von .claude/skills/$name/SKILL.md ab"
    failed=$((failed + 1))
  fi
done
[ "$pairs" -eq 0 ] && echo "keine doppelten Kopien" || echo "$pairs Paar(e) geprüft"

echo
if [ "$failed" -gt 0 ]; then
  echo "$failed Testdatei(en) mit Fehlern."
elif [ "$skipped" -eq 0 ]; then
  echo "Alle Tests grün."
else
  echo "Alle gelaufenen Tests grün, aber nicht alles lief."
fi
[ "$skipped" -eq 0 ] || echo "Ganz oder teilweise übersprungen: $skipped_names"
echo "Übersprungen: $skipped Testdatei(en)."
[ "$failed" -eq 0 ]
