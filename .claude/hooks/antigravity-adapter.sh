#!/usr/bin/env bash
# Übersetzer für Google Antigravity (.agents/hooks.json): Antigravity schickt seinen
# Hooks ein anderes JSON als Claude Code und erwartet eine JSON-Antwort statt eines
# Exitcodes. Dieses Skript übersetzt in beide Richtungen, damit dieselben Hooks wie
# bei Claude Code laufen. Eigene Regeln stehen hier keine.
#
#   bash antigravity-adapter.sh session-start   zeigt offene Handoffs (list-recent-handoffs.sh)
#   bash antigravity-adapter.sh pre-tool        sperrt gefährliche Befehle (block-dangerous-commands.sh)
#
# Antigravity -> Claude Code:
#   run_command  { CommandLine }  -> Bash { command }
#   view_file    { AbsolutePath } -> Read { file_path }
#   grep_search  { SearchPath }   -> Grep { path }
# Exitcode 2 des Hooks wird zu {"decision":"deny","reason":"..."}, sonst {"decision":"allow"}
# ("allow" heißt bei Antigravity: weiter zur normalen Rückfrage, keine Freigabe).
#
# Tests: bash .claude/hooks/tests/test-harness-hooks.sh
# Nur bash, sed, tr und awk; bash 3.2 kompatibel (macOS).
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd)"
payload="$(tr '\r\n' '  ')"

# Roher String-Wert zu einem JSON-Schlüssel. Escapes bleiben stehen, damit der Wert
# unverändert in neues JSON passt.
raw_json() {
  printf '%s' "$payload" |
    sed -E -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1
}

# Text als JSON-String (ohne die äußeren Anführungszeichen).
json_escape() {
  printf '%s' "$1" | tr '\t\r' '  ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
    awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

# Projektordner: erster Eintrag aus workspacePaths, sonst Git-Wurzel, sonst aktueller Ordner.
root="$(printf '%s' "$payload" |
  sed -E -n 's/.*"workspacePaths"[[:space:]]*:[[:space:]]*\[[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' |
  head -n 1 | sed -e 's/\\\\/\//g')"
if [ -z "$root" ] || [ ! -d "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

case "${1:-}" in
  session-start)
    text="$(HANDOFF_AGENT=antigravity CLAUDE_PROJECT_DIR="$root" bash "$HOOKS/list-recent-handoffs.sh" </dev/null 2>/dev/null)"
    if [ -z "$text" ]; then
      echo '{}'
    else
      printf '{"injectSteps":[{"systemMessage":{"systemMessage":"%s"}}]}\n' "$(json_escape "$text")"
    fi
    ;;
  pre-tool)
    claude=""
    if [ -n "$(raw_json CommandLine)" ]; then
      claude="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$(raw_json CommandLine)\"}}"
    elif [ -n "$(raw_json AbsolutePath)" ]; then
      claude="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$(raw_json AbsolutePath)\"}}"
    elif [ -n "$(raw_json SearchPath)" ]; then
      claude="{\"tool_name\":\"Grep\",\"tool_input\":{\"path\":\"$(raw_json SearchPath)\"}}"
    fi
    if [ -n "$claude" ]; then
      reason="$(printf '%s' "$claude" | CLAUDE_PROJECT_DIR="$root" bash "$HOOKS/block-dangerous-commands.sh" 2>&1 >/dev/null)"
      if [ $? -eq 2 ]; then
        printf '{"decision":"deny","reason":"%s"}\n' "$(json_escape "$reason")"
        exit 0
      fi
    fi
    echo '{"decision":"allow"}'
    ;;
  *)
    echo "Aufruf: bash antigravity-adapter.sh session-start|pre-tool" >&2
    ;;
esac
exit 0
