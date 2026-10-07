#!/usr/bin/env bash
# Stop-Hook "Run-Gate" — blockiert das Antwort-Ende, wenn in diesem Zug Code geschrieben,
# danach aber nichts ausgeführt wurde. Der Agent bekommt die Rückmeldung und muss laufen lassen.
#
# WHY Hook statt Regel: "Führe Code aus, bevor du sagst, dass er funktioniert" ist eine Regel, die
# Agenten unter Kontextdruck überspringen. Ein Hook kostet kein Attention-Budget und ist nicht
# verhandelbar (Quelle: Nate Herk, "I Built Another Andrej Karpathy Using Claude", 2026-10).
#
# Abschaltbar, per Default AUS: in .om/config.json den Wert "runGate" auf "an" setzen.
#
# Bewusst grob: "ausgeführt" heißt irgendein Bash-Aufruf nach der letzten Code-Änderung. Ob der Lauf
# das Richtige geprüft hat, entscheidet der Agent und der Abschlussblock — der Hook erzwingt nur,
# dass überhaupt etwas lief. Reine Doku-/Markdown-/JSON-Änderungen lösen nichts aus.
#
# bash 3.2 kompatibel (macOS). Stdin: Hook-JSON mit transcript_path und stop_hook_active.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

grep -qE '"runGate"[[:space:]]*:[[:space:]]*"an"' "$ROOT/.om/config.json" 2>/dev/null || exit 0

EVENT="$(cat)"
export EVENT

python3 - <<'PY'
import json, os, sys

CODE_EXT = {
    ".py", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".sh", ".bash", ".zsh", ".rb", ".go",
    ".rs", ".php", ".java", ".kt", ".swift", ".c", ".cc", ".cpp", ".h", ".cs", ".lua", ".sql", ".ps1",
}
EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}

try:
    event = json.loads(os.environ.get("EVENT", ""))
except Exception:
    sys.exit(0)

# Schutz vor Endlosschleife: nach einem Block darf der Agent beim zweiten Versuch beenden.
if event.get("stop_hook_active"):
    sys.exit(0)

path = event.get("transcript_path")
if not path:
    sys.exit(0)

def is_real_prompt(entry):
    if entry.get("type") != "user" or entry.get("isMeta"):
        return False
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        return not content.lstrip().startswith("<")
    if isinstance(content, list):
        has_result = any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content)
        texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        return not has_result and any(t and not t.lstrip().startswith("<") for t in texts)
    return False

edited = []     # (index, Dateipfad) der Code-Änderungen im aktuellen Zug
last_run = -1   # Index des letzten Bash-Aufrufs im aktuellen Zug
try:
    with open(path, encoding="utf-8") as fh:
        for i, line in enumerate(fh):
            try:
                entry = json.loads(line)
            except Exception:
                continue
            if is_real_prompt(entry):
                edited, last_run = [], -1
                continue
            if entry.get("type") != "assistant":
                continue
            content = entry.get("message", {}).get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = block.get("name")
                args = block.get("input") or {}
                if name == "Bash":
                    last_run = i
                elif name in EDIT_TOOLS:
                    target = args.get("file_path") or args.get("notebook_path") or ""
                    if any(target.endswith(ext) for ext in CODE_EXT):
                        edited.append((i, target))
except OSError:
    sys.exit(0)

unrun = [t for i, t in edited if i > last_run]
if not unrun:
    sys.exit(0)

files = ", ".join(sorted({t.rsplit("/", 1)[-1] for t in unrun})[:5])
print(json.dumps({
    "decision": "block",
    "reason": (
        f"Run-Gate: In diesem Zug wurde Code geschrieben ({files}), danach aber nichts ausgeführt. "
        "Führe den Code oder den passenden Test jetzt aus, zeige die tatsächliche Ausgabe und melde "
        "erst dann, ob es funktioniert. Kann er in dieser Umgebung nicht laufen, sag das ausdrücklich."
    ),
}, ensure_ascii=False))
PY
exit 0
