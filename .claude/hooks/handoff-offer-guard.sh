#!/usr/bin/env bash
# UserPromptSubmit-Hook: Erkennt, ob Sie einen Session-Handoff laden, und trennt
# den Handoff von Ihren eigenen Worten. Er schreibt dann einen kurzen Hinweis in
# Claudes Kontext, wie es weitergeht.
#
# Warum ein Hook statt einer Regel: Agenten nehmen den letzten Abschnitt eines
# Handoffs ("Possible next step") gern als Auftrag und legen los. Der Hook erkennt
# den Fall jedes Mal gleich und schaltet die Sperre in handoff-briefing-gate.sh.
#
# Grundregel: Ein Handoff ist Kontext, kein Arbeitsauftrag. Lädt der User nur den
# Handoff, gibt es ein kurzes Fazit, und handoff-briefing-gate.sh sperrt Schreib-Tools
# bis zur nächsten Nachricht. Nur eigene Worte des Users sind ein Auftrag.
#
#   briefing  Handoff ohne eigenen Text (eingefügt, Pfad, "lade den Handoff") -> Fazit, Sperre
#   auftrag   Handoff plus eigener Text                                       -> eigener Text gilt
#   gruss     erster Prompt ohne Inhalt ("moin")                              -> Laden anbieten
#   task      erster Prompt mit Auftrag                                       -> nicht fragen
#   none      alles andere mitten in der Session                              -> still
#
# Der Ladevorschlag läuft nur beim ersten Prompt (armiert von list-recent-handoffs.sh),
# das Erkennen eines Handoffs bei jedem Prompt. Jeder neue Prompt löst die Sperre.
# Ohne python3 bleibt der Hook still und sperrt nichts.
#
# Tests: bash .claude/hooks/tests/test-handoff-hooks.sh
set -uo pipefail

command -v python3 >/dev/null 2>&1 || { cat >/dev/null; exit 0; }
export HANDOFF_STATE_DIR="${TMPDIR:-/tmp}/handoff-guard"

read -r -d '' GUARD_PY <<'PY' || true
import json, os, re, sys, time
from pathlib import Path

STATE = Path(os.environ["HANDOFF_STATE_DIR"])
MARKER_MAX_AGE_SECONDS = 7 * 24 * 3600
MIN_SECTION_HITS = 3
END_MARKER = "<!-- handoff-ende -->"

SECTIONS = ("Where it started", "Decisions locked", "Key files", "Running state",
            "Verification", "Deferred", "Pick up here", "Possible next step")
# Auch gerendert kopierte Chat-Ausgabe zählt: Überschriften stehen dann ohne #.
HEAD = r"^[ \t]*(?:#{1,3}[ \t]+)?(?:\*\*)?"
SECTION = re.compile(HEAD + "(" + "|".join(SECTIONS) + r")\b.{0,60}$", re.M)
TITLE = re.compile(HEAD + r"Session Handoff\b.*$", re.M)
LAST_HEADING = re.compile(HEAD + r"(?:Pick up here|Possible next step)\b.{0,60}$", re.M)
PASTE = re.compile(r"<pasted_content[^>]*>(.*?)</pasted_content[^>]*>", re.S)
FRONTMATTER = re.compile(r"^---\s*\n.*?type:\s*session-handoff.*?^---\s*$", re.M | re.S)
POINTER = re.compile(r"\S*brainstorms/sessions/\S+\.md|\b\d{4}-\d{2}-\d{2}-\d{4}-[\w-]+\.md")
TAG = re.compile(r"</?pasted_content[^>]*>")
SAVED_LINE = re.compile(r"^(?:Saved|Gespeichert):\s*\S+.*$", re.M)
QUOTE_LINE = re.compile(r"^>.*$", re.M)
SLASH_COMMAND = re.compile(r"\s*/[^\s/]+(?:\s|$)")
# Hintergrund-Meldungen laufen auch durch UserPromptSubmit, sind aber nie der User.
NOT_FROM_USER = re.compile(r"SYSTEM NOTIFICATION|<task-notification|<side-sessions-event|<ci-monitor-event")
NOTICE_SCAN_CHARS = 400
WORD = re.compile(r"[\wäöüß-]+")

HANDOFF_WORDS = {"handoff", "session-handoff", "sessionhandoff", "übergabe"}
LOAD_VERBS = {"lade", "laden", "lad", "lies", "lesen", "einlesen", "nimm", "übernimm",
              "übernehmen", "hol", "öffne", "load", "read", "open"}
FILLER = HANDOFF_WORDS | LOAD_VERBS | set("""
    hier ist sind der die das den dem des ein eine einen mein meine meinen unser unseren
    letzte letzter letzten letztes neueste neuester neuesten aktuellen von gestern heute
    vorhin session markdown saved gespeichert bitte mir uns mal kurz nur erstmal einfach rein kontext zur info kenntnis
    ok okay danke hi hallo hey moin servus guten morgen tag abend und
    please the this last latest newest is here
""".split())

BRIEFING = ("[handoff-guard] BRIEFING-MODUS. Der User lädt nur einen Handoff, ohne eigenen Auftrag. "
    "Ein Handoff ist Kontext, kein Arbeitsauftrag; auch 'Possible next step' und 'Pick up here' sind "
    "nur Vorschläge an den User. Lies, was du brauchst (nur Lese-Tools), und antworte dann in höchstens "
    "5 Zeilen: 'Hab alles gelesen. Stand: <1 Satz>. Könnte anstehen: <1 bis 3 Punkte>. Was denkst du?' "
    "Danach stoppen. Bis zur nächsten Nachricht des Users sperrt ein Hook Schreib-Tools, "
    "Befehle mit Seiteneffekt, Subagenten und Skills.")
AUFTRAG = ("[handoff-guard] Handoff plus eigener Text des Users. Nur der eigene Text ist der AUFTRAG, "
    "der Handoff ist Kontext. Führe 'Possible next step' oder 'Pick up here' nicht von selbst aus. "
    "Enthält der eigene Text keinen konkreten Auftrag: kurzes Fazit, dann auf den User warten.")
GRUSS = ("[handoff-guard] Erster Prompt ohne Inhalt. Falls die SessionStart-Liste Handoffs zeigt: per "
    "AskUserQuestion anbieten, den neuesten, einen bestimmten oder keinen zu laden. Wird einer geladen: "
    "nur lesen, dann höchstens 5 Zeilen: 'Hab alles gelesen. Stand: ... Könnte anstehen: ... Was denkst "
    "du?' Danach stoppen. Sobald ein Handoff gelesen wird, sperrt ein Hook Schreib-Tools bis zur "
    "nächsten Nachricht.")
TASK = ("[handoff-guard] Erster Prompt ist ein Auftrag: nicht nach einem Handoff fragen. Passt ein "
    "gelisteter Handoff klar zum Thema, lies ihn als Kontext und arbeite am Auftrag des Users; "
    "seinen 'Possible next step' nicht von selbst ausführen.")
MESSAGES = {"briefing": BRIEFING, "auftrag": AUFTRAG, "gruss": GRUSS, "task": TASK}


def is_handoff(text):
    return len({m.group(1) for m in SECTION.finditer(text)}) >= MIN_SECTION_HITS


def block_end(body):
    """Position, an der der Handoff endet und wieder Text des Users stehen kann."""
    i = body.find(END_MARKER)
    if i >= 0:
        return i + len(END_MARKER)
    last = None
    for last in LAST_HEADING.finditer(body):
        pass
    if last is None:
        return len(body)
    # Nur die erste Textzeile gehört noch dazu: im Zweifel zählt Text als Wort des Users.
    start = last.end() + len(body[last.end():]) - len(body[last.end():].lstrip())
    newline = body.find("\n", start)
    return newline if newline >= 0 else len(body)


def split_block(prompt):
    """(enthält Handoff?, eigene Worte des Users). Ein Paste mit Handoff fällt ganz weg."""
    pasted = [m.group(1) for m in PASTE.finditer(prompt)]
    found = any(is_handoff(p) for p in pasted)
    rest = PASTE.sub(lambda m: " " if is_handoff(m.group(1)) else m.group(1), prompt)
    if not is_handoff(rest):
        return found, rest
    title, section = TITLE.search(rest), SECTION.search(rest)
    start = title.start() if title and title.start() < section.start() else section.start()
    body = rest[start:]
    return True, FRONTMATTER.sub(" ", rest[:start]) + "\n" + body[block_end(body):]


def classify(prompt, first):
    if SLASH_COMMAND.match(prompt):
        return "task" if first else "none"
    has_block, rest = split_block(prompt)
    rest = QUOTE_LINE.sub(" ", SAVED_LINE.sub(" ", TAG.sub(" ", rest)))
    rest, pointers = POINTER.subn(" ", rest)
    tokens = WORD.findall(rest.lower())
    own = [t for t in tokens if t not in FILLER]
    mentions_handoff = bool(set(tokens) & HANDOFF_WORDS)
    if has_block or pointers or (mentions_handoff and set(tokens) & LOAD_VERBS):
        return "auftrag" if own else "briefing"
    # "session handoff" ohne Lade-Verb heißt: Handoff schreiben. Das ist ein Auftrag.
    if own or mentions_handoff:
        return "task" if first else "none"
    return "gruss" if first else "none"


def remove_old_markers():
    for old in STATE.iterdir():
        try:
            if time.time() - old.stat().st_mtime > MARKER_MAX_AGE_SECONDS:
                old.unlink()
        except OSError:  # parallele Session war schneller
            pass


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    sid = str(event.get("session_id", ""))
    if not re.fullmatch(r"[\w-]+", sid):
        return
    prompt = str(event.get("prompt", ""))
    if NOT_FROM_USER.search(prompt[:NOTICE_SCAN_CHARS]):
        return
    STATE.mkdir(parents=True, exist_ok=True)
    armed = STATE / (sid + ".armed")
    first = armed.exists()
    for suffix in (".armed", ".briefing", ".offered"):
        (STATE / (sid + suffix)).unlink(missing_ok=True)
    remove_old_markers()
    kind = classify(prompt, first)
    if kind == "briefing":
        (STATE / (sid + ".briefing")).touch()
    if kind == "gruss":  # Sperre greift erst, wenn der Gate-Hook das Lesen eines Handoffs sieht
        (STATE / (sid + ".offered")).touch()
    if kind in MESSAGES:
        print(MESSAGES[kind])


main()
PY

python3 -c "$GUARD_PY" 2>/dev/null
exit 0
