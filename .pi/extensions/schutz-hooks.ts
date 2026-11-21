// Pi-Erweiterung: Vor jedem Aufruf von bash, powershell, read und grep fragt sie
// denselben Hook wie Claude Code (.claude/hooks/block-dangerous-commands.sh) und
// sperrt, was er sperrt. Eigene Regeln stehen hier keine.
//
// Pi lädt die Datei nur, wenn Sie dem Ordner vertrauen (Frage beim Start oder /trust).
// Sie braucht keine Pakete, nur Node und bash (unter Windows Git Bash). Fehlt bash
// oder der Hook, lässt sie alles durch: Sie ist eine Bremse, keine Sicherheitsgrenze.
// Tests: bash .claude/hooks/tests/test-harness-hooks.sh
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const HOOK = join(".claude", "hooks", "block-dangerous-commands.sh");
const BLOCKED_EXIT = 2;

// Pi-Werkzeug -> [Werkzeug bei Claude Code, Feld bei Pi, Feld bei Claude Code]
const TOOLS: Record<string, [string, string, string]> = {
  bash: ["Bash", "command", "command"],
  powershell: ["Bash", "command", "command"],
  read: ["Read", "path", "file_path"],
  grep: ["Grep", "path", "path"],
};

export function claudePayload(toolName: string, input: Record<string, unknown>): string | undefined {
  const tool = TOOLS[toolName];
  const value = tool && input ? input[tool[1]] : undefined;
  if (typeof value !== "string") return undefined;
  return JSON.stringify({ tool_name: tool[0], tool_input: { [tool[2]]: value } });
}

export function findRoot(start: string): string | undefined {
  for (let dir = resolve(start); ; dir = dirname(dir)) {
    if (existsSync(join(dir, HOOK))) return dir;
    if (dirname(dir) === dir) return undefined;
  }
}

// Gibt den Grund zurück, wenn der Hook sperrt, sonst undefined.
export function check(cwd: string, toolName: string, input: Record<string, unknown>): string | undefined {
  const payload = claudePayload(toolName, input);
  const root = payload ? findRoot(cwd) : undefined;
  if (!payload || !root) return undefined;
  const run = spawnSync("bash", [join(root, HOOK)], {
    input: payload,
    encoding: "utf8",
    timeout: 10000,
    env: { ...process.env, CLAUDE_PROJECT_DIR: root },
  });
  if (run.status !== BLOCKED_EXIT) return undefined;
  return (run.stderr || "").trim() || "Gesperrt vom Hook block-dangerous-commands.sh";
}

export default function (pi: any) {
  pi.on("tool_call", async (event: any, ctx: any) => {
    const reason = check(ctx?.cwd ?? process.cwd(), event.toolName, event.input);
    if (reason) return { block: true, reason };
    return undefined;
  });
}
