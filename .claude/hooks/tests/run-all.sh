#!/usr/bin/env bash
# Startet alle Hook-Tests nacheinander und prüft, dass die beiden Kopien des
# Handoff-Skills (Claude Code und Codex) gleich sind.
# Lauf: bash .claude/hooks/tests/run-all.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS/../../.." && pwd)"
failed=0

for t in "$TESTS"/test-*.sh; do
  echo "── $(basename "$t")"
  bash "$t" || failed=$((failed + 1))
done

echo "── Skill-Kopien"
if cmp -s "$ROOT/.claude/skills/session-handoff/SKILL.md" "$ROOT/.agents/skills/session-handoff/SKILL.md"; then
  echo "gleich"
else
  echo "FAIL: .agents/skills/session-handoff/SKILL.md weicht von .claude/skills/session-handoff/SKILL.md ab"
  failed=$((failed + 1))
fi

echo
[ "$failed" -eq 0 ] && echo "Alle Tests grün." || echo "$failed Testdatei(en) mit Fehlern."
[ "$failed" -eq 0 ]
