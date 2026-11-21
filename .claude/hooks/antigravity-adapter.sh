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

# JSON-Text zu Klartext, Ergebnis in DECODED. Aufgelöst werden die einfachen Escapes
# (Anführungszeichen, Backslash, Schrägstrich, n, t, r, b, f) und die Schreibweise
# mit Backslash, u und vier Hexziffern für ASCII-Zeichen (0001 bis 007F). Jede andere
# Schreibweise dieser Art lässt sich hier nicht sicher prüfen: Dann ist UNREADABLE=1,
# und der Aufruf wird abgelehnt. Sonst käme "git reset --hard" als U+0026-Kette
# unerkannt durch. Im Quelltext steht kein Backslash-u, damit nichts davon selbst
# als Escape gelesen wird: BS ist ein einzelner Backslash.
BS='\'
DECODED=""
UNREADABLE=0
json_decode() {
  local s="$1" out="" pre hex c
  UNREADABLE=0
  while [ -n "$s" ]; do
    pre="${s%%"$BS"*}"
    out="$out$pre"
    s="${s#"$pre"}"
    [ -n "$s" ] || break
    case "$s" in
      "$BS"u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*)
        hex="${s:2:4}"
        case "$hex" in
          00[0-7][0-9a-fA-F])
            if [ "$hex" = "0000" ]; then
              UNREADABLE=1
            else
              printf -v c "${BS}x${hex:2:2}"
              out="$out$c"
            fi ;;
          *) UNREADABLE=1 ;;
        esac
        s="${s:6}" ;;
      "$BS"u*) UNREADABLE=1; s="${s:2}" ;;
      "$BS$BS"*) out="$out$BS"; s="${s:2}" ;;
      "$BS\""*) out="$out\""; s="${s:2}" ;;
      "$BS"/*) out="$out/"; s="${s:2}" ;;
      "$BS"n*) out="$out"$'\n'; s="${s:2}" ;;
      "$BS"[trbf]*) out="$out "; s="${s:2}" ;;
      *) out="$out$BS"; s="${s:1}" ;;
    esac
  done
  DECODED="$out"
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
    tool="" field="" key=""
    if [ -n "$(raw_json CommandLine)" ]; then
      tool="Bash"; field="command"; key="CommandLine"
    elif [ -n "$(raw_json AbsolutePath)" ]; then
      tool="Read"; field="file_path"; key="AbsolutePath"
    elif [ -n "$(raw_json SearchPath)" ]; then
      tool="Grep"; field="path"; key="SearchPath"
    fi
    if [ -n "$key" ]; then
      json_decode "$(raw_json "$key")"
      if [ "$UNREADABLE" = 1 ]; then
        printf '{"decision":"deny","reason":"%s"}\n' "$(json_escape "Gesperrt vom Adapter antigravity-adapter.sh: Der Aufruf enthält eine Unicode-Schreibweise (Backslash, u und vier Ziffern), die sich nicht sicher prüfen lässt. Schreib den Befehl oder den Pfad mit normalen Zeichen.")"
        exit 0
      fi
      claude="{\"tool_name\":\"$tool\",\"tool_input\":{\"$field\":\"$(json_escape "$DECODED")\"}}"
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
