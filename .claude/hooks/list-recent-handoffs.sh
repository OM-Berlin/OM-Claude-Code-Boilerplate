#!/usr/bin/env bash
# SessionStart hook — surfaces recent session-handoffs so the agent can offer to
# reload one instead of starting cold. Silent when there are none (or the folder
# is absent), so it is a harmless no-op in fresh/empty projects.
#
# Output goes to stdout, which Claude Code injects into the session's context.
# Dieser Hook FRAGT NICHT — er listet nur und "armiert" den UserPromptSubmit-Hook
# handoff-offer-guard.sh. Der sieht den ersten Prompt und entscheidet dann, ob der
# Ladevorschlag noch nötig ist (er entfällt, wenn der User den Handoff selbst
# eingefügt hat). Verhindert die doppelte Nachfrage.
#
# bash 3.2 compatible (macOS default) — no mapfile/readarray.
set -uo pipefail

# stdin-Payload (JSON) lesen — enthält session_id; ohne Payload kein Armieren.
payload="$(cat 2>/dev/null || true)"

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/brainstorms/sessions"
[ -d "$DIR" ] || exit 0

# Files live directly in sessions/ (private/ is a subdir → excluded by -maxdepth 1).
# Filenames start with YYYY-MM-DD-HHmm, so a reverse lexical sort is newest-first.
first="$(find "$DIR" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' 2>/dev/null | sort -r | head -1)"
[ -n "$first" ] || exit 0

field() { grep -m1 -E "^$2:" "$1" 2>/dev/null | sed -E "s/^$2:[[:space:]]*//"; }

# Ab hier steht fest: es gibt Handoffs → Guard für den ersten Prompt armieren.
sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -n "$sid" ]; then
  STATE_DIR="${TMPDIR:-/tmp}/om-handoff-guard"
  mkdir -p "$STATE_DIR" 2>/dev/null && : > "$STATE_DIR/$sid.armed"
fi

echo "── Session-Handoffs in brainstorms/sessions/ (neueste zuerst) ──"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  echo "• $(basename "$f")"
  echo "    topic: $(field "$f" topic) · status: $(field "$f" status) · updated: $(field "$f" updated) · session-id: $(field "$f" session-id)"
done < <(find "$DIR" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' 2>/dev/null | sort -r | head -3)
echo
echo "→ NOCH NICHT fragen. Warte den ersten User-Prompt ab: der Hook handoff-offer-guard.sh sagt dir dann, ob ein Handoff schon eingefügt wurde (nicht fragen) oder nicht (Ladevorschlag per AskUserQuestion). Details: CLAUDE.md → Session-Start-Regel."
exit 0
