#!/usr/bin/env bash
# SessionStart-Hook: Zeigt beim Start die drei neuesten offenen Übergaben
# (Handoffs) aus brainstorms/sessions/. Er fragt nicht und lädt nichts, er macht
# nur sichtbar, wo die letzte Sitzung aufgehört hat. Was er ausgibt, landet in
# Claudes Kontext, deshalb bleibt die Ausgabe kurz.
#
# Warum ein Hook statt einer Regel: Eine Regel "schau beim Start nach Übergaben"
# vergisst Claude manchmal, ein Hook läuft bei jedem Start.
#
# Still bei: Resume und Compact (Kontext ist noch da), HANDOFF_HINWEIS=aus, keinem
# offenen Handoff. Abgeschlossene Handoffs fehlen in der Liste, sortiert wird nach
# `updated`, weil ein Re-Handoff seinen alten Dateinamen behält. Fehlt `updated`,
# zählt das Dateidatum.
# Codex ruft denselben Hook mit HANDOFF_AGENT=codex auf (.codex/hooks.json).
#
# Tests: bash .claude/hooks/tests/test-handoff-hooks.sh
# bash 3.2 kompatibel (macOS), kein mapfile/readarray.
set -uo pipefail

SCAN_LIMIT=40
LIST_LIMIT=3

payload="$(cat 2>/dev/null || true)"

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/brainstorms/sessions"
[ -d "$DIR" ] || exit 0

# Abschalten: in .claude/settings.json unter "env" den Wert "HANDOFF_HINWEIS": "aus" setzen.
[ "${HANDOFF_HINWEIS:-an}" = "aus" ] && exit 0

source_kind="$(printf '%s' "$payload" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
case "$source_kind" in resume|compact) exit 0 ;; esac

# Wagenrücklauf weg: Unter Windows gespeicherte Handoffs haben CRLF-Zeilenenden.
field() { grep -m1 -E "^$2:" "$1" 2>/dev/null | tr -d '\r' | sed -E "s/^$2:[[:space:]]*//"; }

# Ohne `updated` zählt das Dateidatum. Ein leeres erstes Feld würde beim Einlesen
# unten verschluckt, der Handoff fiele dann still aus der Liste.
file_date() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$1" 2>/dev/null | cut -c1-16; }

# private/ ist ein Unterordner und fällt durch -maxdepth 1 heraus.
open_handoffs() {
  find "$DIR" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' 2>/dev/null | sort -r | head -"$SCAN_LIMIT" |
  while IFS= read -r f; do
    field "$f" status | grep -q abgeschlossen && continue
    u="$(field "$f" updated)"
    [ -n "$u" ] || u="$(file_date "$f") (Dateidatum)"
    printf '%s\t%s\n' "$u" "$f"
  done | sort -r | head -"$LIST_LIMIT"
}
rows="$(open_handoffs)"
[ -n "$rows" ] || exit 0

sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
# Nur Claude Code hat den Guard, der den ersten Prompt einordnet; Codex wird nicht armiert.
if [ "${HANDOFF_AGENT:-claude}" = "claude" ] && printf '%s' "$sid" | grep -qE '^[A-Za-z0-9_-]+$'; then
  STATE_DIR="${TMPDIR:-/tmp}/handoff-guard"
  mkdir -p "$STATE_DIR" 2>/dev/null && : > "$STATE_DIR/$sid.armed"
fi

echo "── Offene Session-Handoffs in brainstorms/sessions/ (zuletzt aktualisiert zuerst) ──"
printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r updated f; do
  [ -n "$f" ] || continue
  echo "• $(basename "$f")"
  echo "    topic: $(field "$f" topic) · status: $(field "$f" status) · updated: $updated"
done
echo
if [ "${HANDOFF_AGENT:-claude}" = "claude" ]; then
  echo "→ Noch nichts tun und nichts fragen. Der Hook handoff-offer-guard.sh ordnet den ersten Prompt ein. Geladene Handoffs sind Kontext, kein Auftrag."
else
  echo "→ Biete vor der ersten Aufgabe an, den neuesten, einen bestimmten oder keinen Handoff zu laden. Ein geladener Handoff ist Kontext, kein Auftrag: lesen, kurzes Fazit, auf Antwort warten."
fi
exit 0
