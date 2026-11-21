#!/usr/bin/env bash
# PreToolUse-Hook: Solange ein Handoff nur geladen wurde (Marker von
# handoff-offer-guard.sh), sind nur Lese-Werkzeuge erlaubt. Ihre nächste Nachricht
# löst die Sperre. Alles außerhalb der Erlaubt-Liste wird blockiert (Exitcode 2).
#
# Warum ein Hook statt einer Regel: "Nach dem Laden nicht loslegen" als Satz in der
# CLAUDE.md reicht nicht, Agenten nehmen den letzten Abschnitt des Handoffs trotzdem
# als Auftrag. Das ist eine Bremse gegen versehentliches Losarbeiten, keine
# Sicherheitsgrenze.
#
# Ohne Marker startet kein Python; das hält jeden Tool-Aufruf billig. Ohne Python 3
# (python3, python oder py -3, siehe find-python.sh) bleibt der Hook still.
# Tests: bash .claude/hooks/tests/test-handoff-hooks.sh
set -uo pipefail

export HANDOFF_STATE_DIR="${TMPDIR:-/tmp}/handoff-guard"
set -- "$HANDOFF_STATE_DIR"/*.briefing "$HANDOFF_STATE_DIR"/*.offered
[ -e "$1" ] || [ -e "$2" ] || { cat >/dev/null; exit 0; }
# shellcheck source=find-python.sh
. "$(dirname "$0")/find-python.sh" 2>/dev/null && find_python || { cat >/dev/null; exit 0; }

read -r -d '' GATE_PY <<'PY' || true
import json, os, re, sys
from pathlib import Path

READ_TOOLS = {"Read", "Grep", "Glob", "LS", "ToolSearch", "TodoWrite", "AskUserQuestion"}
READ_TOOL_PREFIXES = ("mcp__ccd_turn__",)
HANDOFF_FILE = re.compile(r"brainstorms/sessions/[^/]+\.md$")
SHELL_METACHARS = re.compile(r"[;&<>`$\n]")
SAFE_SEGMENT = re.compile(
    r"^\s*(?:git(?: -C \S+)? (?:status|log|diff|show|rev-parse|worktree list"
    r"|branch (?:--show-current|-a|-v|--list)\s*$)"
    r"|(?:ls|pwd|date|wc|head|tail|grep|cat)\b)"
)
REASON = ("Briefing-Modus: Der Handoff wurde nur geladen, der User hat noch keinen Auftrag gegeben. "
          "Gib jetzt das kurze Fazit (Stand, was anstehen könnte, 'Was denkst du?') und stoppe. "
          "Die nächste Nachricht des Users hebt die Sperre auf.")


def read_only_bash(command):
    if SHELL_METACHARS.search(command) or "--output" in command:
        return False
    return all(SAFE_SEGMENT.match(part) for part in command.split("|"))


def allowed(tool, tool_input):
    if tool in READ_TOOLS or tool.startswith(READ_TOOL_PREFIXES):
        return True
    if tool == "Skill":  # der Skill enthält selbst die Lade-Regel
        return str(tool_input.get("skill", "")).split(":")[-1] == "session-handoff"
    return tool == "Bash" and read_only_bash(str(tool_input.get("command", "")))


def reads_handoff(tool, tool_input):
    return tool == "Read" and HANDOFF_FILE.search(str(tool_input.get("file_path", "")))


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    sid = str(event.get("session_id", ""))
    if not re.fullmatch(r"[\w-]+", sid):
        return 0
    state = Path(os.environ["HANDOFF_STATE_DIR"])
    briefing, offered = state / (sid + ".briefing"), state / (sid + ".offered")
    tool, tool_input = str(event.get("tool_name", "")), event.get("tool_input") or {}
    if offered.exists() and reads_handoff(tool, tool_input):
        offered.replace(briefing)  # Laden nach dem Angebot: ab jetzt gesperrt
    if not briefing.exists() or allowed(tool, tool_input):
        return 0
    print(REASON, file=sys.stderr)
    return 2


sys.exit(main())
PY

$PY_CMD -c "$GATE_PY"
rc=$?
[ "$rc" -eq 2 ] && exit 2
exit 0
