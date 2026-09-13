#!/usr/bin/env bash
# UserPromptSubmit hook — entscheidet EINMAL pro Session, ob der Agent den
# Handoff-Ladevorschlag noch machen soll.
#
# Hintergrund: Der SessionStart-Hook (list-recent-handoffs.sh) listet vorhandene
# Handoffs, aber er kann den ersten User-Prompt nicht sehen. Wer nach /clear den
# letzten Handoff direkt in die erste Nachricht pastet, wurde bisher trotzdem
# gefragt — doppelt und nervig. Dieser Hook liest den ersten Prompt und sagt dem
# Agenten deterministisch: schon geladen (nicht fragen) oder leer (fragen).
#
# Armiert wird er von list-recent-handoffs.sh (nur wenn es überhaupt Handoffs
# gibt). Er feuert genau einmal pro Session und ist danach still.
#
# bash 3.2 kompatibel (macOS default).
set -uo pipefail

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$sid" ] || exit 0

STATE_DIR="${TMPDIR:-/tmp}/om-handoff-guard"
ARMED="$STATE_DIR/$sid.armed"
[ -f "$ARMED" ] || exit 0          # nicht armiert (keine Handoffs) oder schon verbraucht
rm -f "$ARMED"

# alte Marker aufräumen (best effort)
find "$STATE_DIR" -type f -name '*.armed' -mtime +7 -delete 2>/dev/null

# Sieht der erste Prompt nach einem eingefügten Handoff aus?
# Kriterium: Handoff-Marker UND nennenswerte Länge (ein kurzer Satz über Handoffs
# ist kein eingefügter Handoff).
len=${#payload}
looks_like_handoff=0
if printf '%s' "$payload" | grep -qiE 'Session Handoff|Pick up here|Where it started|Decisions locked|brainstorms/sessions'; then
  [ "$len" -gt 800 ] && looks_like_handoff=1
fi

if [ "$looks_like_handoff" -eq 1 ]; then
  echo "[handoff-guard] Der erste Prompt enthält bereits einen Session-Handoff. NICHT nachfragen, ob ein Handoff geladen werden soll — Kontext ist da. Direkt mit der Aufgabe weitermachen."
else
  echo "[handoff-guard] Kein Handoff im ersten Prompt. Falls die SessionStart-Liste Handoffs zeigt: JETZT per AskUserQuestion anbieten, den neuesten (oder einen bestimmten) zu laden — oder keinen. Danach nie wieder in dieser Session fragen."
fi
exit 0
