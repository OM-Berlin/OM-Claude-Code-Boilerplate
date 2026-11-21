#!/usr/bin/env bash
# Tests für die Schutz-Hooks in Codex, Antigravity und Pi. Jedes Programm schickt
# sein eigenes JSON, in der Form aus seiner offiziellen Doku. Geprüft wird der echte
# Aufruf aus .codex/hooks.json und .agents/hooks.json sowie die Pi-Erweiterung
# .pi/extensions/schutz-hooks.ts (nur wenn Node TypeScript direkt laden kann).
# Lauf: bash .claude/hooks/tests/test-harness-hooks.sh
set -uo pipefail
# Der Schalter aus der eigenen Shell darf die Tests nicht abschalten.
unset OM_SCHUTZ_HOOK

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
. "$ROOT/.claude/hooks/find-python.sh"
find_python || { echo "Python 3 fehlt, Test übersprungen (gesucht: python3, python, py -3)"; exit 0; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

# Testprojekt mit eigenem Git, Kopie der Hooks und einem offenen Handoff.
PROJ="$WORK/projekt"
mkdir -p "$PROJ/.claude" "$PROJ/.codex" "$PROJ/.agents" "$PROJ/brainstorms/sessions"
cp -R "$ROOT/.claude/hooks" "$PROJ/.claude/"
cp "$ROOT/.codex/hooks.json" "$PROJ/.codex/"
cp "$ROOT/.agents/hooks.json" "$PROJ/.agents/"
printf -- '---\ntype: session-handoff\ntopic: Testthema\nstatus: aktiv\nupdated: 2026-11-20 10:00\n---\n' \
  > "$PROJ/brainstorms/sessions/2026-11-20-1000-testthema.md"
git -C "$PROJ" init -q -b feature 2>/dev/null || { git -C "$PROJ" init -q && git -C "$PROJ" checkout -q -b feature; }

# hook_cmds <hooks.json> <Ereignis> [<Werkzeug>]: die Befehle, die bei diesem Ereignis
# (und zu diesem Werkzeugnamen passenden matcher) laufen. Versteht beide Formate:
# Codex {"hooks": {Ereignis: [...]}} und Antigravity {name: {Ereignis: [...]}}.
# Mit HOOK_FIELD=commandWindows kommt der Befehl, den Codex unter Windows nimmt.
hook_cmds() {
  HOOK_FIELD="${HOOK_FIELD:-command}" $PY_CMD - "$1" "$2" "${3:-}" <<'PY'
import json, os, re, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
event, tool = sys.argv[2], sys.argv[3]
key = os.environ["HOOK_FIELD"]
blocks = [data["hooks"]] if "hooks" in data else [v for v in data.values() if isinstance(v, dict)]
for block in blocks:
    if block.get("enabled", True) is False:
        continue
    for group in block.get(event, []):
        matcher = group.get("matcher", "")
        if tool and matcher not in ("", "*") and not re.fullmatch(matcher.strip("^$"), tool):
            continue
        for handler in group.get("hooks", [group]):
            print(handler.get(key, ""))
PY
}

# json <python-ausdruck>: baut das Eingabe-JSON nach J; P ist der Projektordner.
# Absichtlich nie als "$(json "{a,b}")": bash 3.2 löst {a,b} in dieser Schachtelung auf.
json() { J="$(P="$PROJ" $PY_CMD -c "import json,os; P=os.environ['P']; print(json.dumps($1))")"; }

# run <hooks.json> <Ereignis> <Werkzeug> <json>: setzt OUT, ERR und RC.
run() {
  local cmd
  cmd="$(hook_cmds "$1" "$2" "$3")"
  if [ -z "$cmd" ]; then OUT=""; ERR="kein Hook für $2/$3"; RC=99; return; fi
  # RUNNER: die Shell, in der das Programm den Befehl startet (Standard bash -c).
  OUT="$(cd "$PROJ" && printf '%s' "$4" | ${RUNNER:-bash -c} "$cmd" 2>"$WORK/err")"; RC=$?
  ERR="$(cat "$WORK/err")"
}

# field <json> <python-ausdruck auf d>: liest einen Wert aus der JSON-Antwort.
field() { printf '%s' "$1" | $PY_CMD -c "import json,sys; d=json.load(sys.stdin); print($2)" 2>/dev/null; }

# --- Codex (.codex/hooks.json) ---
CODEX="$PROJ/.codex/hooks.json"
codex_common="'session_id':'c1','transcript_path':None,'cwd':P,'model':'gpt-5.5','permission_mode':'default'"

json "{$codex_common,'hook_event_name':'SessionStart','source':'startup'}"; run "$CODEX" SessionStart "" "$J"
case "$OUT" in *"testthema.md"*"Biete"*) ok ;; *) bad "Codex SessionStart zeigt offenen Handoff" "$OUT $ERR" ;; esac
json "{$codex_common,'hook_event_name':'SessionStart','source':'resume'}"; run "$CODEX" SessionStart "" "$J"
[ -z "$OUT" ] && ok || bad "Codex SessionStart bei resume still" "$OUT"

codex_bash() { # codex_bash <befehl> <erwarteter Exitcode>
  CMD="$1" json "{$codex_common,'hook_event_name':'PreToolUse','turn_id':'t1','tool_name':'Bash','tool_use_id':'u1','tool_input':{'command':os.environ['CMD']}}"; run "$CODEX" PreToolUse Bash "$J"
  [ "$RC" = "$2" ] && ok || bad "Codex PreToolUse '$1': Exitcode $RC statt $2" "$ERR"
}
codex_bash 'git reset --hard' 2
codex_bash 'rm -rf ~' 2
codex_bash 'cat .env.local' 2
codex_bash 'git status' 0
codex_bash 'ls -la' 0
case "$ERR" in "") ok ;; *) bad "Codex: erlaubter Befehl ohne Meldung" "$ERR" ;; esac
codex_bash 'git reset --hard' 2
case "$ERR" in *"Gesperrt vom Hook"*) ok ;; *) bad "Codex: Sperrgrund auf stderr" "$ERR" ;; esac

# --- Codex unter Windows (Feld commandWindows) ---
# Codex startet Hooks unter Windows mit cmd.exe oder PowerShell, nicht mit bash. Der Befehl
# in commandWindows darf deshalb nur Zeichen enthalten, die dort nichts bedeuten, und ruft
# bash über einen Git-Alias auf (git liegt unter Windows im PATH, bash oft nicht).
# PowerShell macht aus Exitcode 2 eine 1 (Codex-Issue 54072). Deshalb sperrt der Hook dort
# mit JSON auf stdout (permissionDecision deny) und Exitcode 0, unabhängig von der Shell.
# Geprüft wird er hier mit bash, mit sh und, falls installiert, mit PowerShell (pwsh).
win_cmds="$(HOOK_FIELD=commandWindows hook_cmds "$CODEX" SessionStart; HOOK_FIELD=commandWindows hook_cmds "$CODEX" PreToolUse Bash)"
[ "$(printf '%s\n' "$win_cmds" | grep -c .)" = 2 ] && ok || bad "Codex: commandWindows fehlt bei SessionStart oder PreToolUse" "$win_cmds"
case "$win_cmds" in *'$'* | *"'"* | *'%'* | *'&'* | *'|'* | *';'* | *'`'*) bad "Codex: commandWindows enthält Zeichen, die cmd.exe oder PowerShell auswerten" "$win_cmds" ;; *) ok ;; esac
win_runners="bash -c|sh -c"
command -v pwsh >/dev/null 2>&1 && win_runners="$win_runners|pwsh -NoProfile -NonInteractive -Command"
IFS='|' read -r -a win_list <<<"$win_runners"
for RUNNER in "${win_list[@]}"; do
  json "{$codex_common,'hook_event_name':'SessionStart','source':'startup'}"; HOOK_FIELD=commandWindows run "$CODEX" SessionStart "" "$J"
  case "$OUT" in *"testthema.md"*"Biete"*) ok ;; *) bad "Codex Windows ($RUNNER) SessionStart zeigt offenen Handoff" "$OUT $ERR" ;; esac
  for c in 'git reset --hard:deny' 'cat .env.local:deny' 'git status:allow'; do
    CMD="${c%:*}" json "{$codex_common,'hook_event_name':'PreToolUse','turn_id':'t1','tool_name':'Bash','tool_use_id':'u1','tool_input':{'command':os.environ['CMD']}}"
    HOOK_FIELD=commandWindows run "$CODEX" PreToolUse Bash "$J"
    [ "$RC" = 0 ] && ok || bad "Codex Windows ($RUNNER) '${c%:*}': Exitcode $RC statt 0" "$ERR"
    if [ "${c##*:}" = deny ]; then
      case "$(field "$OUT" "d['hookSpecificOutput']['permissionDecision'] + ' ' + d['hookSpecificOutput']['permissionDecisionReason']")" in
        "deny Gesperrt vom Hook"*) ok ;; *) bad "Codex Windows ($RUNNER) '${c%:*}': JSON mit deny erwartet" "$OUT $ERR" ;; esac
    else
      [ -z "$OUT" ] && ok || bad "Codex Windows ($RUNNER) '${c%:*}': erlaubt heißt keine Ausgabe" "$OUT"
    fi
  done
done
unset RUNNER

# --- Antigravity (.agents/hooks.json) ---
AGY="$PROJ/.agents/hooks.json"
agy_common="'conversationId':'ec33ebf9-0cba-4100-8142-c61503f6c587','workspacePaths':[P],'transcriptPath':'/x/transcript.jsonl','artifactDirectoryPath':'/x','modelName':'gemini-3.6-flash-medium'"

json "{$agy_common}"; run "$AGY" SessionStart "" "$J"
msg="$(field "$OUT" "d['injectSteps'][0]['systemMessage']['systemMessage']")"
case "$msg" in *"testthema.md"*"Biete"*) ok ;; *) bad "Antigravity SessionStart: injectSteps mit offenem Handoff" "$OUT $ERR" ;; esac
json "{$agy_common}"; cmd="$(hook_cmds "$AGY" SessionStart)"
OUT="$(cd "$PROJ" && printf '%s' "$J" | HANDOFF_HINWEIS=aus bash -c "$cmd")"
[ "$(field "$OUT" "d")" = "{}" ] && ok || bad "Antigravity SessionStart ohne Liste: {}" "$OUT"

agy_tool() { # agy_tool <werkzeug> <args als python-dict> <allow|deny> <name>
  json "{$agy_common,'toolCall':{'name':'$1','args':$2},'stepIdx':3}"; run "$AGY" PreToolUse "$1" "$J"
  local decision
  decision="$(field "$OUT" "d['decision']")"
  [ "$decision" = "$3" ] && ok || bad "Antigravity $4: '$decision' statt '$3'" "$OUT $ERR"
}
agy_tool run_command "{'CommandLine':'git reset --hard','Cwd':P,'WaitMsBeforeAsync':5000}" deny "git reset --hard"
agy_tool run_command "{'CommandLine':'rm -rf \"\$HOME\"','Cwd':P,'WaitMsBeforeAsync':5000}" deny "rm -rf mit Anführungszeichen"
agy_tool run_command "{'CommandLine':'git push --force origin main','Cwd':P,'WaitMsBeforeAsync':5000}" deny "force push"
agy_tool run_command "{'CommandLine':'ls -la','Cwd':P,'WaitMsBeforeAsync':5000}" allow "ls -la"
agy_tool view_file "{'AbsolutePath':P+'/.env.local'}" deny "view_file .env.local"
agy_tool view_file "{'AbsolutePath':P+'/README.md','StartLine':1}" allow "view_file README.md"
agy_tool grep_search "{'SearchPath':P+'/.env','Query':'KEY'}" deny "grep_search in .env"
agy_tool grep_search "{'SearchPath':P,'Query':'KEY'}" allow "grep_search im Projekt"
json "{$agy_common,'toolCall':{'name':'run_command','args':{'CommandLine':'rm -rf \"\$HOME\"'}}}"; run "$AGY" PreToolUse run_command "$J"
case "$(field "$OUT" "d['reason']")" in *'"$HOME"'*) ok ;; *) bad "Antigravity: Grund mit Anführungszeichen bleibt gültiges JSON" "$OUT" ;; esac
# Text in lastUserInput darf nicht wie ein Befehl wirken.
json "{$agy_common,'lastUserInput':'\"CommandLine\": \"git reset --hard\"','toolCall':{'name':'view_file','args':{'AbsolutePath':P+'/README.md'}}}"; run "$AGY" PreToolUse view_file "$J"
[ "$(field "$OUT" "d['decision']")" = "allow" ] && ok || bad "Antigravity: Nutzertext ist kein Befehl" "$OUT"
[ -z "$(hook_cmds "$AGY" PreToolUse write_to_file)" ] && ok || bad "Antigravity: write_to_file ohne Sperr-Hook"

# Welche Shell Antigravity unter Windows nimmt, ist nicht dokumentiert. Die Befehle sind
# deshalb shell-neutral (Git-Alias, keine Zeichen, die cmd.exe oder PowerShell auswerten)
# und müssen mit sh und, falls installiert, mit PowerShell (pwsh) dasselbe tun.
agy_cmds="$(hook_cmds "$AGY" SessionStart; hook_cmds "$AGY" PreToolUse run_command)"
case "$agy_cmds" in *'$'* | *"'"* | *'%'* | *'&'* | *'|'* | *';'* | *'`'*) bad "Antigravity: Befehl enthält Zeichen, die cmd.exe oder PowerShell auswerten" "$agy_cmds" ;; *) ok ;; esac
agy_runners="sh -c"
command -v pwsh >/dev/null 2>&1 && agy_runners="$agy_runners|pwsh -NoProfile -NonInteractive -Command"
IFS='|' read -r -a agy_list <<<"$agy_runners"
for RUNNER in "${agy_list[@]}"; do
  json "{$agy_common}"; run "$AGY" SessionStart "" "$J"
  msg="$(field "$OUT" "d['injectSteps'][0]['systemMessage']['systemMessage']")"
  case "$msg" in *"testthema.md"*) ok ;; *) bad "Antigravity ($RUNNER) SessionStart" "$OUT $ERR" ;; esac
  agy_tool run_command "{'CommandLine':'git reset --hard','Cwd':P}" deny "($RUNNER) git reset --hard"
  agy_tool run_command "{'CommandLine':'ls -la','Cwd':P}" allow "($RUNNER) ls -la"
done
unset RUNNER

# JSON-Escapes der Form uXXXX (mit Backslash davor) und \/ dürfen die Sperre nicht
# umgehen. Das JSON wird hier als Rohtext gebaut, weil Pythons json.dumps ASCII nie
# so schreibt. Im Quelltext steht @u für Backslash plus u.
agy_raw() { # agy_raw <roher Wert von CommandLine> <allow|deny> <name>
  local val="${1//@u/\\u}"
  run "$AGY" PreToolUse run_command '{"conversationId":"x","toolCall":{"name":"run_command","args":{"CommandLine":"'"$val"'","Cwd":"/x"}}}'
  local decision
  decision="$(field "$OUT" "d['decision']")"
  [ "$decision" = "$2" ] && ok || bad "Antigravity $3: '$decision' statt '$2'" "$OUT $ERR"
}
agy_raw 'git status @u0026@u0026 git reset --hard' deny "U+0026 statt &&, dann git reset --hard"
agy_raw 'npm test @u0026@u0026 rm -rf ~' deny "U+0026 statt &&, dann rm -rf ~"
agy_raw '@u0063at .env.local' deny "U+0063 statt c, dann at .env.local"
agy_raw 'cat .env@u002elocal' deny "U+002e im Dateinamen"
agy_raw 'rm -rf \/' deny "rm -rf mit escapetem Schrägstrich"
agy_raw 'git status @u003b git reset --hard' deny "U+003b statt ;"
agy_raw 'git push --force origin main' deny "force push im Klartext"
agy_raw 'ls @u002dla' allow "harmloses U+002d wird zu -"
agy_raw 'git status' allow "git status im Klartext"
agy_raw 'echo \\@u0026' allow "doppelter Backslash vor u0026 ist kein &"
agy_raw 'echo caf@u00e9' deny "nicht lesbares U+00e9"
case "$(field "$OUT" "d['reason']")" in *"Unicode"*) ok ;; *) bad "Antigravity: Grund nennt die Unicode-Schreibweise" "$OUT" ;; esac
agy_raw 'echo @u0000' deny "U+0000"

# Windows-Pfade: Backslash plus n oder t bleibt Backslash plus Buchstabe. Die Rückwärts-
# striche entstehen erst zur Laufzeit, damit keine Werkzeugschicht sie vorher auflöst.
B="$(printf '\134')"
agy_env() { # agy_env <befehl mit # für Backslash> <allow|deny>
  CMD="${1//#/$B}" agy_tool run_command "{'CommandLine':os.environ['CMD'],'Cwd':P}" "$2" "${1//#/$B}"
}
agy_env 'git -C C:#new#app reset --hard' deny
agy_env 'git -C C:#new#app status' allow
agy_env 'rm -r -fo C:#temp#build' allow
agy_env 'cmd /c "git reset --hard"' deny
# Ungültiges UTF-8 darf die Prüfung nicht aushebeln, auch nicht in einer UTF-8-Umgebung.
cmd="$(hook_cmds "$AGY" PreToolUse run_command)"
OUT="$(cd "$PROJ" && printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"git reset --hard \377"}}}' | LC_ALL=en_US.UTF-8 bash -c "$cmd" 2>&1)"
[ "$(field "$OUT" "d['decision']")" = deny ] && ok || bad "Antigravity: ungültiges UTF-8 mit git reset --hard wird abgelehnt" "$OUT"
# Endet der Hook unerwartet (weder 0 noch 2), lehnt der Adapter ab, statt durchzulassen.
mkdir -p "$WORK/kaputt/hooks"
cp "$ROOT/.claude/hooks/antigravity-adapter.sh" "$WORK/kaputt/hooks/"
printf '%s\n' '#!/usr/bin/env bash' 'exit 3' >"$WORK/kaputt/hooks/block-dangerous-commands.sh"
OUT="$(printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}' | bash "$WORK/kaputt/hooks/antigravity-adapter.sh" pre-tool 2>&1)"
[ "$(field "$OUT" "d['decision']")" = deny ] && ok || bad "Antigravity: Hook endet mit 3, Adapter lehnt ab" "$OUT"

# --- Pi (.pi/extensions/schutz-hooks.ts) ---
if ! command -v node >/dev/null 2>&1; then
  echo "Node fehlt, Pi-Teil übersprungen"
else
  cat > "$WORK/pi-test.mjs" <<'JS'
import { pathToFileURL } from "node:url";
const [file, cwd] = process.argv.slice(2);
const ext = await import(pathToFileURL(file).href);
let handler;
ext.default({ on: (name, fn) => { if (name === "tool_call") handler = fn; } });
const cases = [
  ["bash", { command: "git reset --hard" }, true],
  ["bash", { command: "rm -rf ~" }, true],
  ["bash", { command: "git status" }, false],
  ["powershell", { command: "Get-Content .env.local" }, true],
  ["read", { path: ".env.local" }, true],
  ["read", { path: "README.md" }, false],
  ["grep", { pattern: "KEY", path: ".env" }, true],
  ["grep", { pattern: "KEY" }, false],
  ["edit", { path: ".env.local", edits: [] }, false],
];
// bash unter Windows: Git Bash an den üblichen Orten, nie das bash von WSL.
const { findBash, makeBashResolver } = ext;
const same = (got, want, label) => console.log(got === want ? "ok" : `FAIL ${label}: ${got} statt ${want}`);
const fs = (...files) => (p) => files.includes(p);
const winEnv = (extra = {}) => ({ ProgramFiles: "C:\\Program Files", LOCALAPPDATA: "C:\\Users\\a\\AppData\\Local", ...extra });
same(findBash("darwin", {}, () => false), "bash", "macOS: bash aus dem PATH");
same(findBash("linux", {}, () => false), "bash", "Linux: bash aus dem PATH");
same(findBash("win32", winEnv({ PATH: "C:\\Windows\\System32" }), fs("C:\\Program Files\\Git\\bin\\bash.exe")),
  "C:\\Program Files\\Git\\bin\\bash.exe", "Windows: Git Bash unter Program Files");
same(findBash("win32", winEnv({ PATH: "" }), fs("C:\\Users\\a\\AppData\\Local\\Programs\\Git\\bin\\bash.exe")),
  "C:\\Users\\a\\AppData\\Local\\Programs\\Git\\bin\\bash.exe", "Windows: Git Bash im Benutzerordner");
same(findBash("win32", winEnv({ PATH: "C:\\Tools\\Git\\cmd;C:\\Windows" }), fs("C:\\Tools\\Git\\cmd\\git.exe", "C:\\Tools\\Git\\bin\\bash.exe")),
  "C:\\Tools\\Git\\bin\\bash.exe", "Windows: bash neben git auf dem PATH");
same(findBash("win32", winEnv({ Path: "C:\\Windows\\System32" }), fs("C:\\Windows\\System32\\bash.exe")),
  undefined, "Windows: bash.exe aus System32 ist WSL und zählt nicht");
same(findBash("win32", winEnv({ PATH: "C:\\Users\\a\\AppData\\Local\\Microsoft\\WindowsApps" }), fs("C:\\Users\\a\\AppData\\Local\\Microsoft\\WindowsApps\\bash.exe")),
  undefined, "Windows: bash.exe aus WindowsApps zählt nicht");
same(findBash("win32", winEnv({ PATH: "C:\\Windows\\System32;C:\\msys64\\usr\\bin" }), fs("C:\\Windows\\System32\\bash.exe", "C:\\msys64\\usr\\bin\\bash.exe")),
  "C:\\msys64\\usr\\bin\\bash.exe", "Windows: anderes bash im PATH wird genommen, WSL übersprungen");
same(findBash("win32", winEnv({ PATH: "C:\\Windows" }), () => false), undefined, "Windows: ohne bash undefined");
{
  const lines = [];
  const resolve = makeBashResolver(() => undefined, (m) => lines.push(m));
  const a = resolve(), b = resolve();
  same(`${a}|${b}|${lines.length}`, "undefined|undefined|1", "ohne bash: genau eine Meldung, Aufruf bleibt offen");
  same(/Git Bash/.test(lines[0] || ""), true, "Meldung nennt Git Bash");
}
// Windows-Zweig von check(): bash.exe aus Git, Pfad mit Schrägstrichen, Projektordner in
// CLAUDE_PROJECT_DIR, JSON auf stdin; scheitert der Start, bleibt der Aufruf offen.
same(ext.hookPath("C:\\Users\\Jürgen Müller\\Lehrgang KI"),
  "C:/Users/Jürgen Müller/Lehrgang KI/.claude/hooks/block-dangerous-commands.sh", "Windows: Hook-Pfad mit / statt \\");
{
  const calls = [];
  const gitBash = "C:\\Program Files\\Git\\bin\\bash.exe";
  const spawn = (status, extra = {}) => (cmd, args, opts) => { calls.push({ cmd, args, opts }); return { status, stderr: "Gesperrt vom Hook x\n", ...extra }; };
  const why = ext.check(cwd, "powershell", { command: "git reset --hard" }, { bash: () => gitBash, spawn: spawn(2) });
  same(why, "Gesperrt vom Hook x", "Windows: Sperrgrund aus stderr");
  same(calls[0].cmd, gitBash, "Windows: startet bash.exe aus Git");
  same(/\\/.test(calls[0].args[0]), false, "Windows: Hook-Pfad ohne Rückwärtsstriche");
  same(calls[0].opts.env.CLAUDE_PROJECT_DIR, ext.findRoot(cwd), "Windows: Projektordner in CLAUDE_PROJECT_DIR");
  same(JSON.parse(calls[0].opts.input).tool_name, "Bash", "Windows: PowerShell-Befehl geht als Bash an den Hook");
  same(calls[0].opts.env.HOOK_AUSGABE, "", "HOOK_AUSGABE aus der Shell wird für den Hook geleert");
  same(ext.check(cwd, "bash", { command: "git status" }, { bash: () => gitBash, spawn: spawn(0) }), undefined, "Windows: Exitcode 0 lässt durch");
  same(ext.check(cwd, "bash", { command: "git reset --hard" }, { bash: () => gitBash, spawn: spawn(null, { error: new Error("ENOENT") }) }),
    undefined, "Windows: bash startet nicht, Aufruf bleibt offen");
  same(ext.check(cwd, "bash", { command: "git reset --hard" }, { bash: () => undefined, spawn: spawn(2) }), undefined, "ohne bash kein Start");
}
for (const [toolName, input, blocked] of cases) {
  const result = await handler({ type: "tool_call", toolName, toolCallId: "t1", input }, { cwd });
  const got = Boolean(result && result.block);
  const why = result && result.reason ? result.reason : "";
  console.log(got === blocked && (!got || why.includes("Gesperrt")) ? "ok" : `FAIL ${toolName} ${JSON.stringify(input)}: block=${got}`);
}
// HOOK_AUSGABE=json aus der Shell des Nutzers ließe den Hook mit 0 enden; Pi darf das nicht.
process.env.HOOK_AUSGABE = "json";
{
  const result = await handler({ type: "tool_call", toolName: "bash", toolCallId: "t2", input: { command: "git reset --hard" } }, { cwd });
  console.log(result && result.block ? "ok" : "FAIL HOOK_AUSGABE=json aus der Shell lässt git reset --hard durch");
}
delete process.env.HOOK_AUSGABE;
JS
  mkdir -p "$PROJ/.pi/extensions" && cp "$ROOT/.pi/extensions/schutz-hooks.ts" "$PROJ/.pi/extensions/"
  out="$(node --experimental-strip-types --no-warnings "$WORK/pi-test.mjs" \
    "$PROJ/.pi/extensions/schutz-hooks.ts" "$PROJ/brainstorms" 2>&1)"
  case "$out" in
    *ERR_UNKNOWN_FILE_EXTENSION* | *"bad option"*) echo "Node kann TypeScript nicht direkt laden, Pi-Teil übersprungen" ;;
    *)
      while IFS= read -r line; do
        case "$line" in ok) ok ;; *) bad "Pi: $line" ;; esac
      done <<EOF
$out
EOF
      ;;
  esac
fi

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
