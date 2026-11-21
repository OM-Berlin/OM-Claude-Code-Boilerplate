#!/usr/bin/env bash
# Black-Box-Tests der drei Handoff-Hooks: JSON rein wie von Claude Code, Ausgabe,
# Exit-Code und Marker-Dateien raus. Lauf: bash .claude/hooks/tests/test-handoff-hooks.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"

# Die Tests bauen ihr JSON mit Python. Gesucht wird wie in den Hooks (find-python.sh).
. "$HOOKS/find-python.sh"
find_python || { echo "Python 3 fehlt, Test übersprungen (gesucht: python3, python, py -3)"; exit 0; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export TMPDIR="$WORK/tmp"
export CLAUDE_PROJECT_DIR="$WORK/proj"
STATE="$TMPDIR/handoff-guard"
mkdir -p "$TMPDIR" "$STATE" "$CLAUDE_PROJECT_DIR/brainstorms/sessions"

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

reset() { rm -f "$STATE"/*; }
arm()   { : > "$STATE/s1.armed"; }
guard() { # guard <prompt> [sid]
  PROMPT="$1" SID="${2:-s1}" $PY_CMD -c 'import json,os;print(json.dumps({"session_id":os.environ["SID"],"prompt":os.environ["PROMPT"]}))' \
    | bash "$HOOKS/handoff-offer-guard.sh"
}
gate() { # gate <tool> [wert für command, skill und file_path] [sid]; setzt GATE_RC
  TOOL="$1" CMD="${2:-}" SID="${3:-s1}" $PY_CMD -c 'import json,os;c=os.environ["CMD"];print(json.dumps({"session_id":os.environ["SID"],"tool_name":os.environ["TOOL"],"tool_input":{"command":c,"skill":c,"file_path":c}}))' \
    | bash "$HOOKS/handoff-briefing-gate.sh" >/dev/null 2>"$WORK/gate.err"
  GATE_RC=$?
}
expect_class() { # expect_class <name> <prompt> <text-im-output|-> <marker 0/1> [armed]
  reset; [ "${5:-}" = armed ] && arm
  out="$(guard "$2")"
  if [ "$3" = "-" ]; then
    [ -z "$out" ] && ok || bad "$1: erwartete Stille" "$out"
  else
    case "$out" in *"$3"*) ok ;; *) bad "$1: erwartete '$3'" "$out" ;; esac
  fi
  if [ -f "$STATE/s1.briefing" ]; then m=1; else m=0; fi
  [ "$m" = "$4" ] && ok || bad "$1: briefing-Marker=$m, erwartet $4"
}

NEW_BLOCK='# Session Handoff: Thema

> Briefing, kein Auftrag.

## Where it started
Text.

## Decisions locked + what shipped
- a

## Key files for next session
- b

## Running state
- none

## Possible next step
Vorschlag.
<!-- handoff-ende -->'

OLD_BLOCK='# Session Handoff: Alt

## Where it started
Text.

## Decisions locked + what shipped
- a

## Running state
- none

## Pick up here
Mach Paket 3 fertig.'

# --- Guard: eingefügter Handoff ---
expect_class "Block allein"            "$NEW_BLOCK" "BRIEFING" 1
expect_class "Altformat allein"        "$OLD_BLOCK" "BRIEFING" 1
expect_class "In pasted_content"       "<pasted_content id=\"1\">
$NEW_BLOCK
</pasted_content id=\"1\">" "BRIEFING" 1
expect_class "Mit Füllwörtern"         "Hier der Handoff:

$NEW_BLOCK" "BRIEFING" 1
expect_class "Mit Saved-Zeile"         "Saved: /a/b/brainstorms/sessions/2026-11-04-0846-x.md

$NEW_BLOCK" "BRIEFING" 1
expect_class "Block + Auftrag danach"  "$NEW_BLOCK

Bitte fix jetzt den Login-Bug." "AUFTRAG" 0
expect_class "Auftrag davor"           "Fix den Login-Bug.

$OLD_BLOCK" "AUFTRAG" 0
expect_class "Altformat + Auftrag"     "$OLD_BLOCK

Prüf zuerst die Migration." "AUFTRAG" 0
expect_class "Auftrag außerhalb Tag"   "Prüf die Migration.
<pasted_content id=\"1\">
$OLD_BLOCK
</pasted_content id=\"1\">" "AUFTRAG" 0

# --- Guard: kopierte Chat-Ausgabe (gerendert, ohne #, mit Vorspann) ---
RENDERED='Session Handoff: Thema
Where it started
Text.
Decisions locked + what shipped
Punkt.
Key files for next session
Datei.
Running state
none
Pick up here
Mach Paket 3 fertig.'
expect_class "Gerendert im Tag"        "<pasted_content id=\"1\">
Saved: /a/brainstorms/sessions/2026-11-04-0846-x.md
$RENDERED
</pasted_content id=\"1\">" "BRIEFING" 1
expect_class "Agenten-Vorspann im Tag" "<pasted_content id=\"1\">
Alles ist gemergt und gepusht, die Datei liegt bereit.

$RENDERED
</pasted_content id=\"1\">" "BRIEFING" 1
expect_class "Gerendert ohne Tag"      "$RENDERED" "BRIEFING" 1
expect_class "Codefence ohne Tag"      "Saved: /a/brainstorms/sessions/2026-11-04-0846-x.md

\`\`\`markdown
$NEW_BLOCK
\`\`\`" "BRIEFING" 1
expect_class "Eigener Text vor Tag"    "Bitte prüf erst die Migration.
<pasted_content id=\"1\">
$RENDERED
</pasted_content id=\"1\">" "AUFTRAG" 0
expect_class "Fremder Paste ist Text"  "<pasted_content id=\"1\">
Bau bitte die Rechnung. Where it started war gestern.
</pasted_content id=\"1\">" "-" 0

# --- Guard: Laden per Zeiger oder Befehl ---
expect_class "Pfad allein"             "brainstorms/sessions/2026-11-04-0846-fehler.md" "BRIEFING" 1
expect_class "Lies Pfad"               "Lies /a/brainstorms/sessions/2026-11-04-0846-fehler.md" "BRIEFING" 1
expect_class "Lade-Befehl"             "Lade den neuesten Handoff" "BRIEFING" 1
expect_class "Lies Pfad + Auftrag"     "Lies brainstorms/sessions/2026-11-04-0846-fehler.md und fix den Bug" "AUFTRAG" 0
expect_class "Lade + Auftrag"          "Lade den Handoff und mach Paket 3" "AUFTRAG" 0

# --- Guard: keine Handoffs, keine Fehlalarme ---
LONG="Ich möchte, dass du am Skill Session Handoff arbeitest. Pick up here ist ein schlechter Name, und brainstorms/sessions wird oft gelesen. $(printf 'Mehr Text dazu. %.0s' $(seq 1 80))"
expect_class "Regression: Erwähnung"   "$LONG" "Auftrag" 0 armed
expect_class "Erwähnung, nicht erste"  "$LONG" "-" 0
expect_class "Handoff schreiben"       "session handoff" "-" 0
expect_class "Mach Handoff"            "mach mal einen handoff" "-" 0
expect_class "Slash-Befehl"            "/session-handoff" "-" 0
expect_class "Slash-Befehl armiert"    "/session-handoff" "Auftrag" 0 armed
expect_class "Handoff-Skill lesen"     "Lies den Handoff-Skill" "-" 0

# --- Guard: erster Prompt ---
expect_class "Gruß armiert"            "moin" "AskUserQuestion" 0 armed
expect_class "Gruß mitten in Session"  "moin" "-" 0
expect_class "Handoff schreiben, erst" "session handoff" "Auftrag" 0 armed
expect_class "Handoff bitte, erst"     "handoff bitte" "Auftrag" 0 armed
expect_class "Absoluter Pfad"          "/home/anna/projekt/brainstorms/sessions/2026-11-04-0846-x.md" "BRIEFING" 1
expect_class "Security-Zeile davor"    "> Security: 1 value(s) redacted.

$NEW_BLOCK" "BRIEFING" 1
expect_class "Lade mir den Handoff"    "lad mir den letzten handoff rein" "BRIEFING" 1
expect_class "Auftrag direkt am Block" "$RENDERED
Fix den Login-Bug." "AUFTRAG" 0
expect_class "Gespeichert-Zeile"       "Gespeichert: /a/brainstorms/sessions/2026-11-04-0846-x.md (Commit abc, not pushed)

$NEW_BLOCK" "BRIEFING" 1

# --- Guard: Hintergrund-Meldungen sind nie der User ---
reset; arm; : > "$STATE/s1.briefing"
out="$(guard '[SYSTEM NOTIFICATION - NOT USER INPUT]
<task-notification> Agent fertig, lies brainstorms/sessions/2026-11-04-0846-x.md </task-notification>')"
[ -z "$out" ] && ok || bad "Meldung muss still sein" "$out"
[ -f "$STATE/s1.briefing" ] && ok || bad "Meldung darf Sperre nicht lösen"
[ -f "$STATE/s1.armed" ] && ok || bad "Meldung darf den ersten Prompt nicht verbrauchen"

# --- Gate: Sperre erst, wenn nach dem Angebot ein Handoff gelesen wird ---
reset; arm; guard "moin" >/dev/null
gate Write; [ "$GATE_RC" = 0 ] && ok || bad "Nach Angebot ohne Laden frei"
gate Read "/a/src/app.py"; gate Write; [ "$GATE_RC" = 0 ] && ok || bad "Fremde Datei lesen sperrt nicht"
gate Read "/a/brainstorms/sessions/2026-11-04-0846-x.md"; [ "$GATE_RC" = 0 ] && ok || bad "Handoff lesen muss gehen"
gate Write; [ "$GATE_RC" = 2 ] && ok || bad "Nach Laden gesperrt"
guard "Mach Paket 3" >/dev/null; gate Write; [ "$GATE_RC" = 0 ] && ok || bad "Nächster Prompt löst auch diese Sperre"
expect_class "Auftrag armiert"         "Bau mir eine Rechnung" "Auftrag" 0 armed
reset; arm; out="$(guard 'Bau mir eine Rechnung')"
case "$out" in *AskUserQuestion*) bad "Auftrag darf kein Angebot auslösen" "$out" ;; *) ok ;; esac
[ -f "$STATE/s1.armed" ] && bad "armed muss verbraucht sein" || ok
out="$(guard 'Noch ein Auftrag')"; [ -z "$out" ] && ok || bad "Zweiter Prompt muss still sein" "$out"

# --- Guard: Marker-Lebenszyklus ---
reset; guard "$NEW_BLOCK" >/dev/null; guard "Ok, mach Paket 3" >/dev/null
[ -f "$STATE/s1.briefing" ] && bad "Nächster Prompt muss Sperre lösen" || ok
reset; guard "$NEW_BLOCK" >/dev/null; guard "$NEW_BLOCK" >/dev/null
[ -f "$STATE/s1.briefing" ] && ok || bad "Erneutes Laden muss wieder sperren"
reset; out="$(guard 'x' '../../evil')"; ls "$STATE" | grep -q evil && bad "session_id ungefiltert" || ok
out="$(printf 'kaputt' | bash "$HOOKS/handoff-offer-guard.sh")"; [ $? -eq 0 ] && [ -z "$out" ] && ok || bad "Kaputtes JSON muss still durchgehen"

# --- Gate ---
reset
gate Write; [ "$GATE_RC" = 0 ] && ok || bad "Ohne Marker frei"
: > "$STATE/s1.briefing"
for t in Write Edit MultiEdit NotebookEdit Agent Workflow Skill mcp__beispiel__create_item mcp__beispiel__send_message; do
  gate "$t"; [ "$GATE_RC" = 2 ] && ok || bad "$t muss gesperrt sein (rc=$GATE_RC)"
done
grep -q "Briefing" "$WORK/gate.err" && ok || bad "Sperrgrund fehlt auf stderr"
for t in Read Grep Glob LS ToolSearch TodoWrite AskUserQuestion mcp__ccd_turn__update_plan mcp__ccd_turn__wrap_up; do
  gate "$t"; [ "$GATE_RC" = 0 ] && ok || bad "$t muss frei sein (rc=$GATE_RC)"
done
for c in "git status --short" "git log --oneline abc123..HEAD" "git log -5 | head -3" "git -C /a/b status" "git diff --stat" "git branch --show-current" "ls -la" "pwd" "date" "grep -n x f.md | wc -l"; do
  gate Bash "$c"; [ "$GATE_RC" = 0 ] && ok || bad "Bash frei: $c (rc=$GATE_RC)"
done
for c in "rm -rf x" "git status; rm x" "git status && touch y" "cat a > b" "git branch -D x" "git push" "git commit -m x" 'ls $(rm x)' "npm install" "git log --output=x" "ls | xargs rm" "python3 -c 1" "bash ~/x/set_title.sh Thema"; do
  gate Bash "$c"; [ "$GATE_RC" = 2 ] && ok || bad "Bash gesperrt: $c (rc=$GATE_RC)"
done
gate Bash "git branch -v -D x"; [ "$GATE_RC" = 2 ] && ok || bad "git branch -v -D muss gesperrt sein"
gate Skill "session-handoff"; [ "$GATE_RC" = 0 ] && ok || bad "session-handoff-Skill muss frei sein"
gate Skill "meinplugin:session-handoff"; [ "$GATE_RC" = 0 ] && ok || bad "session-handoff aus Plugin muss frei sein"
gate Skill "grilling"; [ "$GATE_RC" = 2 ] && ok || bad "Anderer Skill muss gesperrt sein"
gate Write "" s2; [ "$GATE_RC" = 0 ] && ok || bad "Andere Session darf nicht gesperrt sein"

# --- SessionStart-Liste ---
SD="$CLAUDE_PROJECT_DIR/brainstorms/sessions"
mk() { printf -- '---\ntopic: %s\nupdated: %s\nstatus: %s\n---\n' "$2" "$3" "$4" > "$SD/$1"; }
start() { printf '{"session_id":"s1","source":"%s"}' "$1" | bash "$HOOKS/list-recent-handoffs.sh"; }
mk 2026-01-01-0900-alt-aktualisiert.md "Alt aktualisiert" "2026-03-01 10:00" aktiv
mk 2026-02-01-0900-mitte.md "Mitte" "2026-02-01 09:00" blockiert
mk 2026-02-15-0900-fertig.md "Fertig" "2026-02-15 09:00" abgeschlossen
reset; out="$(start clear)"
case "$out" in *"Alt aktualisiert"*"Mitte"*) ok ;; *) bad "Sortierung nach updated" "$out" ;; esac
case "$out" in *Fertig*) bad "Abgeschlossene gehören nicht in die Liste" ;; *) ok ;; esac
[ -f "$STATE/s1.armed" ] && ok || bad "clear muss armieren"
for s in resume compact; do
  reset; out="$(start "$s")"
  [ -z "$out" ] && ok || bad "$s muss still sein" "$out"
  [ -f "$STATE/s1.armed" ] && bad "$s darf nicht armieren" || ok
done
reset; out="$(start startup)"; [ -f "$STATE/s1.armed" ] && ok || bad "startup muss armieren"
reset; out="$(HANDOFF_AGENT=codex start startup)"
case "$out" in *"Alt aktualisiert"*"Biete"*) ok ;; *) bad "Codex-Modus zeigt Liste und Angebot" "$out" ;; esac
[ -f "$STATE/s1.armed" ] && bad "Codex darf nicht armieren" || ok
reset; out="$(printf '{"session_id":"../../x","source":"startup"}' | bash "$HOOKS/list-recent-handoffs.sh")"
[ -e "$WORK/x.armed" ] && bad "session_id im Start-Hook ungefiltert" || ok
reset; out="$(HANDOFF_HINWEIS=aus start startup)"; [ -z "$out" ] && ok || bad "HANDOFF_HINWEIS=aus muss still sein" "$out"
[ -f "$STATE/s1.armed" ] && bad "aus darf nicht armieren" || ok

# Handoff ohne `updated`: erscheint mit Dateidatum, fällt nicht still aus der Liste.
rm -f "$SD"/*.md
printf -- '---\ntopic: %s\nstatus: %s\n---\n' "Ohne Datum" aktiv > "$SD/2026-03-01-0900-ohne-updated.md"
mk 2026-03-02-0900-mit-updated.md "Mit Datum" "2026-03-02 09:00" aktiv
reset; out="$(start clear)"
case "$out" in *"ohne-updated.md"*"Ohne Datum"*"(Dateidatum)"*) ok ;; *) bad "Handoff ohne updated muss mit Dateidatum gelistet werden" "$out" ;; esac
case "$out" in *"mit-updated.md"*) ok ;; *) bad "Handoff mit updated fehlt neben dem ohne updated" "$out" ;; esac
rm -f "$SD"/*.md
printf -- '---\ntopic: %s\nstatus: %s\n---\n' "Nur dieser" aktiv > "$SD/2026-03-03-0900-nur-ohne.md"
reset; out="$(start clear)"
case "$out" in *"Nur dieser"*) ok ;; *) bad "Einziger Handoff ohne updated darf nicht verschwinden" "$out" ;; esac
[ -f "$STATE/s1.armed" ] && ok || bad "Handoff ohne updated muss trotzdem armieren"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
