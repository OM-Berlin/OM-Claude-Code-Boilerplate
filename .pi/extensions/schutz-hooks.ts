// Pi-Erweiterung: Vor jedem Aufruf von bash, powershell, read und grep fragt sie
// denselben Hook wie Claude Code (.claude/hooks/block-dangerous-commands.sh) und
// sperrt, was er sperrt. Eigene Regeln stehen hier keine.
//
// Pi lädt die Datei nur, wenn Sie dem Ordner vertrauen (Frage beim Start oder /trust).
// Sie braucht keine Pakete, nur Node und bash. Unter Windows sucht sie Git Bash an den
// üblichen Orten (Program Files, Benutzerordner, neben git) und nimmt nie das bash von
// WSL. Fehlt bash oder der Hook, lässt sie alles durch und meldet das einmal auf stderr:
// Sie ist eine Bremse, keine Sicherheitsgrenze. Unter Windows nur mit Attrappen geprüft.
// Tests: bash .claude/hooks/tests/test-harness-hooks.sh
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve, win32 } from "node:path";

const HOOK = join(".claude", "hooks", "block-dangerous-commands.sh");
const BLOCKED_EXIT = 2;

// Ordner, in denen bash.exe ein Starter für WSL ist (versteht keine Windows-Pfade).
const WSL_DIRS = ["\\windows\\system32", "\\windows\\sysnative", "\\windows\\syswow64", "\\windowsapps"];

type Env = Record<string, string | undefined>;

// Pfad zu einem bash, das die Hook-Skripte ausführen kann, sonst undefined.
// Außerhalb von Windows genügt "bash" aus dem PATH.
export function findBash(
  platform: string = process.platform,
  env: Env = process.env,
  exists: (path: string) => boolean = existsSync,
): string | undefined {
  if (platform !== "win32") return "bash";
  const candidates: string[] = [];
  const bases = [env.ProgramFiles, env["ProgramFiles(x86)"], env.LOCALAPPDATA ? win32.join(env.LOCALAPPDATA, "Programs") : undefined];
  for (const base of bases) if (base) candidates.push(win32.join(base, "Git", "bin", "bash.exe"));
  const dirs = (env.PATH ?? env.Path ?? "").split(";").filter(Boolean);
  for (const dir of dirs) {
    // git.exe liegt in ...\Git\cmd oder ...\Git\bin, bash.exe in ...\Git\bin
    if (exists(win32.join(dir, "git.exe")) || exists(win32.join(dir, "git.cmd"))) {
      candidates.push(win32.join(dir, "bash.exe"), win32.join(dir, "..", "bin", "bash.exe"));
    }
  }
  for (const candidate of candidates) if (exists(candidate)) return candidate;
  for (const dir of dirs) {
    if (WSL_DIRS.some((wsl) => dir.toLowerCase().replace(/[\\/]+$/, "").endsWith(wsl))) continue;
    const candidate = win32.join(dir, "bash.exe");
    if (exists(candidate)) return candidate;
  }
  return undefined;
}

// Sucht bash beim ersten Aufruf und merkt sich das Ergebnis. Fehlt bash, gibt es genau
// eine Meldung; die Aufrufe laufen dann ungeprüft weiter (die Sperre ist nicht aktiv).
export function makeBashResolver(find: () => string | undefined = findBash, log: (msg: string) => void = console.error) {
  let searched = false;
  let found: string | undefined;
  return () => {
    if (!searched) {
      searched = true;
      found = find();
      if (!found) {
        log("schutz-hooks: Git Bash wurde nicht gefunden, die Sperre gefährlicher Befehle ist nicht aktiv. Installieren Sie Git für Windows (es bringt Git Bash mit) und starten Sie Pi neu.");
      }
    }
    return found;
  };
}

const resolveBash = makeBashResolver();

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

// Pfad zum Hook. Git Bash versteht C:/Pfad mit Schrägstrichen sicherer als Rückwärtsstriche.
export function hookPath(root: string): string {
  return join(root, HOOK).replace(/\\/g, "/");
}

// Austauschbar nur für die Tests (Windows-Zweig ohne Windows prüfen).
type Deps = { bash?: () => string | undefined; spawn?: typeof spawnSync };

// Gibt den Grund zurück, wenn der Hook sperrt, sonst undefined.
export function check(cwd: string, toolName: string, input: Record<string, unknown>, deps: Deps = {}): string | undefined {
  const payload = claudePayload(toolName, input);
  const root = payload ? findRoot(cwd) : undefined;
  if (!payload || !root) return undefined;
  const bash = (deps.bash ?? resolveBash)();
  if (!bash) return undefined;
  const run = (deps.spawn ?? spawnSync)(bash, [hookPath(root)], {
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
