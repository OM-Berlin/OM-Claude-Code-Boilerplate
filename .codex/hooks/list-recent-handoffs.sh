#!/usr/bin/env bash
# SessionStart hook — surfaces recent session-handoffs so the agent can offer to
# reload one instead of starting cold. Silent when there are none (or the folder
# is absent), so it is a harmless no-op in fresh/empty projects.
#
# Output goes to stdout, which Codex injects into the session's context.
# The behavior rule ("ask the user which to load") lives in CLAUDE.md; this hook
# only surfaces the raw list deterministically.
#
# bash 3.2 compatible (macOS default) — no mapfile/readarray.
set -uo pipefail

ROOT="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-}}"
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIR="$ROOT/brainstorms/sessions"
[ -d "$DIR" ] || exit 0

# Files live directly in sessions/ (private/ is a subdir → excluded by -maxdepth 1).
# Filenames start with YYYY-MM-DD-HHmm, so a reverse lexical sort is newest-first.
first="$(find "$DIR" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' 2>/dev/null | sort -r | head -1)"
[ -n "$first" ] || exit 0

field() { grep -m1 -E "^$2:" "$1" 2>/dev/null | sed -E "s/^$2:[[:space:]]*//"; }

echo "── Session-Handoffs in brainstorms/sessions/ (neueste zuerst) ──"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  echo "• $(basename "$f")"
  echo "    topic: $(field "$f" topic) · status: $(field "$f" status) · updated: $(field "$f" updated) · session-id: $(field "$f" session-id)"
done < <(find "$DIR" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' 2>/dev/null | sort -r | head -3)
echo
echo "→ Bevor du die erste Aufgabe startest: biete dem User an, den neuesten (oder einen bestimmten) Handoff zu laden — oder keinen. Beim Laden das gewählte File lesen und den Kontext übernehmen. Details: CLAUDE.md, Abschnitt Am Ende jeder Sitzung."
exit 0
