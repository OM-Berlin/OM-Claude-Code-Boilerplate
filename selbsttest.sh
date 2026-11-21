#!/usr/bin/env bash
# Hat diese Datei selbst Windows-Zeilenenden (CRLF), läuft sie ohne sie noch einmal. Die Zeile endet mit #, damit ein \r dahinter nur Kommentar ist.
if grep -q "$(printf '\r')" "$0" 2>/dev/null; then tr -d '\r' <"$0" | SELBSTTEST_DIR="$(dirname "$0")" bash -s; exit $?; fi #
# =========================================================================
# selbsttest.sh: prüft in wenigen Sekunden, ob die Hooks auf diesem Rechner laufen.
#
#   bash selbsttest.sh
#
# Unter Windows starten Sie das in Git Bash (im Ordner Rechtsklick, dann "Open Git Bash
# here"). Die Ausgabe nennt die Versionen von bash, Git, Python, Node und Claude Code und
# startet jeden Hook einmal mit einem Probe-Aufruf. Sie können sie vollständig kopieren
# und Ihrer Lehrgangsleitung schicken: Sie enthält den Ordnerpfad und Versionen, aber
# keine Schlüssel und keine Inhalte Ihrer Dateien. Das Skript ändert nichts im Projekt.
# Ausführlicher prüft: bash .claude/hooks/tests/run-all.sh
# Tests: bash .claude/hooks/tests/test-selbsttest.sh
# bash 3.2 kompatibel (macOS), läuft auch unter Git Bash (Windows).
# =========================================================================
set -u
cd "${SELBSTTEST_DIR:-$(dirname "$0")}" || exit 1
HOOKS=".claude/hooks"
probleme=0
TMP_SELBST="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/selbsttest-$$")"
mkdir -p "$TMP_SELBST"
trap 'rm -rf "$TMP_SELBST"' EXIT

zeile()  { printf '  %-14s %s\n' "$1" "$2"; }
gut()    { printf '  ok       %s\n' "$1"; }
hinweis() { printf '  Hinweis  %s\n' "$1"; [ -n "${2:-}" ] && printf '           %s\n' "$2"; return 0; }
fehler() {
  probleme=$((probleme + 1))
  printf '  FEHLER   %s\n' "$1"
  [ -n "${2:-}" ] && printf '           %s\n' "$2"
  return 0
}
erste_zeile() { "$@" 2>&1 </dev/null | head -n 1; }

echo "Selbsttest Startpaket Claude Code, $(date '+%Y-%m-%d %H:%M')"
echo "Ordner: $(pwd)"
echo
echo "Versionen:"
system="$(uname -s 2>/dev/null)"
zeile "System" "$system $(uname -r 2>/dev/null)"
zeile "bash" "${BASH_VERSION:-unbekannt}"
zeile "Git" "$(command -v git >/dev/null 2>&1 && erste_zeile git --version || echo fehlt)"
PY_CMD=""
if . "$HOOKS/find-python.sh" 2>/dev/null && find_python; then
  zeile "Python" "$(erste_zeile $PY_CMD --version) (Aufruf: $PY_CMD)"
else
  zeile "Python" "fehlt (gesucht: python3, python, py -3)"
fi
zeile "Node" "$(command -v node >/dev/null 2>&1 && erste_zeile node --version || echo "fehlt (nur für Pi nötig)")"
zeile "Claude Code" "$(command -v claude >/dev/null 2>&1 && erste_zeile claude --version || echo "kein Befehl claude (Desktop-App?)")"
zeile "autocrlf" "$(git config core.autocrlf 2>/dev/null || echo "nicht gesetzt")"
echo

echo "Umgebung:"
case "$system" in
  MINGW* | MSYS* | CYGWIN*) gut "Git Bash unter Windows" ;;
  Darwin) gut "macOS" ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      hinweis "Das ist WSL, nicht Git Bash. Claude Code für Windows startet die Hooks mit Git Bash." \
        "Starten Sie den Selbsttest dort: im Ordner Rechtsklick, dann \"Open Git Bash here\"."
    else
      gut "Linux"
    fi ;;
  *) hinweis "Unbekanntes System: $system" ;;
esac
command -v git >/dev/null 2>&1 || fehler "Git fehlt." "Installieren Sie Git (unter Windows: Git für Windows, es bringt Git Bash mit)."
case "$(pwd)" in
  *OneDrive* | *Dropbox* | *iCloud*)
    hinweis "Der Ordner liegt in einem synchronisierten Ordner (OneDrive, Dropbox oder iCloud)." \
      "Das geht meist, kann aber beim Arbeiten stören. Besser: ein Ordner wie C:\\Projekte\\name." ;;
esac
if [ "${#PWD}" -gt 150 ]; then
  hinweis "Der Ordnerpfad ist sehr lang (${#PWD} Zeichen). Windows scheitert ab 260 Zeichen je Datei." \
    "Verschieben Sie den Ordner näher an das Laufwerk, etwa nach C:\\Projekte."
fi
echo

echo "Zeilenenden und Dateien:"
crlf=""
for f in "$HOOKS"/*.sh "$HOOKS"/tests/*.sh einrichten.sh selbsttest.sh; do
  [ -f "$f" ] || continue
  if grep -q "$(printf '\r')" "$f"; then
    crlf="$crlf $f"
    fehler "$f hat Windows-Zeilenenden (CRLF). So läuft das Skript nicht."
  fi
done
if [ -z "$crlf" ]; then
  gut "alle Skripte mit LF-Zeilenenden"
else
  # perl liegt Git für Windows und macOS bei; sed versteht \r nicht überall.
  echo "           Abhilfe in Git Bash: perl -pi -e 's/\\r\$//'$crlf"
fi
if [ -f .claude/settings.json ] && grep -q "block-dangerous-commands.sh" .claude/settings.json; then
  gut ".claude/settings.json hängt die Hooks ein"
else
  fehler ".claude/settings.json fehlt oder hängt den Schutz-Hook nicht ein." "Entpacken Sie das Startpaket neu."
fi
echo

echo "Hooks (je ein Probe-Aufruf):"
export CLAUDE_PROJECT_DIR="$(pwd)"
export TMPDIR="$TMP_SELBST" # Marker der Handoff-Hooks landen hier und werden danach gelöscht
probe() { # probe <hook> <json> [argument]: setzt RC und OUT
  OUT="$(printf '%s' "$2" | bash "$HOOKS/$1" ${3:+"$3"} 2>&1)"
  RC=$?
}
probe block-dangerous-commands.sh '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}'
if [ "$RC" = 2 ]; then gut "block-dangerous-commands.sh sperrt git reset --hard"
else fehler "block-dangerous-commands.sh sperrt git reset --hard nicht (Exitcode $RC)" "$(printf '%s' "$OUT" | head -n 2)"; fi
probe block-dangerous-commands.sh '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
if [ "$RC" = 0 ]; then gut "block-dangerous-commands.sh lässt git status durch"
else fehler "block-dangerous-commands.sh sperrt auch git status (Exitcode $RC)" "$(printf '%s' "$OUT" | head -n 2)"; fi
probe list-recent-handoffs.sh '{"source":"startup"}'
if [ "$RC" = 0 ]; then gut "list-recent-handoffs.sh läuft"
else fehler "list-recent-handoffs.sh endet mit Exitcode $RC" "$(printf '%s' "$OUT" | head -n 2)"; fi
probe format-after-edit.sh '{"tool_name":"Write","tool_input":{"file_path":"gibt-es-nicht.txt"}}'
if [ "$RC" = 0 ]; then gut "format-after-edit.sh läuft"
else fehler "format-after-edit.sh endet mit Exitcode $RC" "$(printf '%s' "$OUT" | head -n 2)"; fi
probe antigravity-adapter.sh '{"toolCall":{"name":"run_command","args":{"CommandLine":"git reset --hard"}}}' pre-tool
case "$OUT" in *'"deny"'*) gut "antigravity-adapter.sh übersetzt und sperrt" ;;
  *) fehler "antigravity-adapter.sh sperrt nicht" "$(printf '%s' "$OUT" | head -n 2)" ;; esac
if [ -n "$PY_CMD" ]; then
  probe handoff-offer-guard.sh '{"session_id":"selbsttest","prompt":"Lade die Übergabe"}'
  case "$OUT" in
    *"BRIEFING-MODUS"*"lädt"*) gut "handoff-offer-guard.sh erkennt das Laden eines Handoffs (Umlaute heil)" ;;
    *"BRIEFING-MODUS"*) fehler "handoff-offer-guard.sh läuft, aber Umlaute kommen verstümmelt an" "$(printf '%s' "$OUT" | cut -c1-100 | head -n 1)" ;;
    *) fehler "handoff-offer-guard.sh erkennt das Laden eines Handoffs nicht" "$(printf '%s' "$OUT" | head -n 2)" ;;
  esac
  probe handoff-briefing-gate.sh '{"session_id":"selbsttest","tool_name":"Write","tool_input":{"file_path":"x.txt"}}'
  if [ "$RC" = 2 ]; then gut "handoff-briefing-gate.sh sperrt Schreiben nach dem Laden"
  else fehler "handoff-briefing-gate.sh sperrt nicht (Exitcode $RC)" "$(printf '%s' "$OUT" | head -n 2)"; fi
  probe handoff-briefing-gate.sh '{"session_id":"selbsttest","tool_name":"Read","tool_input":{"file_path":"x.txt"}}'
  if [ "$RC" = 0 ]; then gut "handoff-briefing-gate.sh lässt Lesen durch"
  else fehler "handoff-briefing-gate.sh sperrt auch Lesen (Exitcode $RC)"; fi
else
  hinweis "Python 3 fehlt: handoff-offer-guard.sh und handoff-briefing-gate.sh setzen still aus." \
    "Alles andere läuft. Wer die beiden will: Python von python.org installieren, dann neu testen."
fi
echo

if [ "$probleme" = 0 ]; then
  echo "Ergebnis: alles in Ordnung."
  exit 0
fi
echo "Ergebnis: $probleme Problem(e). Kopieren Sie diese Ausgabe vollständig und schicken Sie sie Ihrer Lehrgangsleitung."
exit 1
