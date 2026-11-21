#!/usr/bin/env bash
# Tests für selbsttest.sh: Er meldet "alles in Ordnung", wenn die Hooks laufen, und nennt
# sonst das Problem samt Abhilfe (Windows-Zeilenenden, kaputter Hook, fehlendes Python).
# Lauf: bash .claude/hooks/tests/test-selbsttest.sh
set -uo pipefail
unset OM_SCHUTZ_HOOK

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

kit() { # kit <ordner>: Kopie mit allem, was der Selbsttest braucht
  mkdir -p "$1/.claude"
  cp "$ROOT/selbsttest.sh" "$ROOT/einrichten.sh" "$1/"
  cp -R "$ROOT/.claude/hooks" "$ROOT/.claude/settings.json" "$1/.claude/"
}
lauf() { # lauf <ordner> [PATH-Vorsatz]: setzt OUT und RC
  OUT="$(cd "$1" && PATH="${2:-}$PATH" bash selbsttest.sh 2>&1)"; RC=$?
}

# 1. Alles da: Erfolg, Versionen stehen in der Ausgabe.
kit "$WORK/gut"; lauf "$WORK/gut"
[ "$RC" = 0 ] && ok || bad "intaktes Paket: Exitcode $RC statt 0" "$OUT"
case "$OUT" in *"alles in Ordnung"*) ok ;; *) bad "intaktes Paket: 'alles in Ordnung' fehlt" "$OUT" ;; esac
case "$OUT" in *"bash "*"Git "*"Python "*"Claude Code "*) ok ;; *) bad "Versionen fehlen" "$OUT" ;; esac
case "$OUT" in *FEHLER*) bad "intaktes Paket: keine FEHLER-Zeile erwartet" "$OUT" ;; *) ok ;; esac
[ -z "$(ls -A "$WORK/gut" | grep -v -e '^selbsttest.sh$' -e '^einrichten.sh$' -e '^.claude$')" ] && ok || bad "Selbsttest darf im Ordner nichts anlegen" "$(ls -A "$WORK/gut")"

# 2. Ordner mit Leerzeichen und Umlauten, wie unter Windows üblich.
kit "$WORK/Jürgen Müller/Lehrgang KI"; lauf "$WORK/Jürgen Müller/Lehrgang KI"
[ "$RC" = 0 ] && ok || bad "Pfad mit Leerzeichen und Umlauten: Exitcode $RC" "$OUT"

# 3. Ein Hook mit Windows-Zeilenenden: Fehler mit Dateinamen und Abhilfe.
kit "$WORK/crlf"
sed 's/$/\r/' "$ROOT/.claude/hooks/block-dangerous-commands.sh" > "$WORK/crlf/.claude/hooks/block-dangerous-commands.sh"
lauf "$WORK/crlf"
[ "$RC" = 1 ] && ok || bad "CRLF: Exitcode $RC statt 1" "$OUT"
case "$OUT" in *"block-dangerous-commands.sh hat Windows-Zeilenenden"*"perl -pi"*) ok ;; *) bad "CRLF: Datei und Abhilfe fehlen" "$OUT" ;; esac

# 3b. Alles mit CRLF, auch der Selbsttest: Er läuft trotzdem und nennt die Abhilfe,
# und die Abhilfe repariert das Paket wirklich.
kit "$WORK/alles-crlf"
find "$WORK/alles-crlf" -name '*.sh' -exec perl -pi -e 's/\n/\r\n/' {} +
lauf "$WORK/alles-crlf"
[ "$RC" = 1 ] && ok || bad "alles CRLF: Exitcode $RC statt 1" "$OUT"
case "$OUT" in *"selbsttest.sh hat Windows-Zeilenenden"*"Ergebnis:"*) ok ;; *) bad "alles CRLF: Selbsttest muss trotzdem bis zum Ergebnis laufen" "$OUT" ;; esac
fix="$(printf '%s\n' "$OUT" | sed -n 's/^ *Abhilfe in Git Bash: //p' | head -n 1)"
[ -n "$fix" ] && (cd "$WORK/alles-crlf" && eval "$fix") && lauf "$WORK/alles-crlf"
[ "$RC" = 0 ] && ok || bad "alles CRLF: nach der Abhilfe muss der Selbsttest grün sein" "$fix / $OUT"

# 4. Ein Hook, der nichts sperrt.
kit "$WORK/kaputt"
printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$WORK/kaputt/.claude/hooks/block-dangerous-commands.sh"
lauf "$WORK/kaputt"
[ "$RC" = 1 ] && ok || bad "kaputter Hook: Exitcode $RC statt 1" "$OUT"
case "$OUT" in *"sperrt git reset --hard nicht"*) ok ;; *) bad "kaputter Hook: Meldung fehlt" "$OUT" ;; esac

# 5. Nur Platzhalter aus dem Microsoft Store statt Python: kein Fehler, aber ein Hinweis.
mkdir -p "$WORK/store"
for n in python3 python py; do
  printf '#!/bin/sh\necho "Python wurde nicht gefunden" >&2\nexit 49\n' > "$WORK/store/$n"
  chmod +x "$WORK/store/$n"
done
kit "$WORK/ohne-py"; lauf "$WORK/ohne-py" "$WORK/store:"
[ "$RC" = 0 ] && ok || bad "ohne Python: Exitcode $RC statt 0" "$OUT"
case "$OUT" in *"Python 3 fehlt"*"setzen still aus"*) ok ;; *) bad "ohne Python: Hinweis fehlt" "$OUT" ;; esac

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
