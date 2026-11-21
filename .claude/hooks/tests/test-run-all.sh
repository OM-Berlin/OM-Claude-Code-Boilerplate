#!/usr/bin/env bash
# Tests für run-all.sh: Es läuft als Kopie in einem nachgebauten Projekt mit kleinen
# Attrappen-Tests. Geprüft wird die Zusammenfassung: grün, rot, übersprungen (jede
# Testdatei, die "übersprungen" ausgibt, zählt) und der Vergleich doppelter Skill-Kopien.
# Lauf: bash .claude/hooks/tests/test-run-all.sh
# bash 3.2 kompatibel (macOS).
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

R="$WORK/projekt"
fresh() { # fresh <test-name:verhalten> ...   verhalten: gruen | skip | rot
  local spec name how
  rm -rf "$R"; mkdir -p "$R/.claude/hooks/tests"
  cp "$TESTS/run-all.sh" "$R/.claude/hooks/tests/"
  for spec in "$@"; do
    name="${spec%%:*}"; how="${spec#*:}"
    case "$how" in
      gruen) printf '#!/usr/bin/env bash\necho "1 ok, 0 fehlgeschlagen"\n' ;;
      skip)  printf '#!/usr/bin/env bash\necho "Quelle fehlt, Vergleich übersprungen"\necho "1 ok, 0 fehlgeschlagen"\n' ;;
      rot)   printf '#!/usr/bin/env bash\necho "FAIL: kaputt"\nexit 1\n' ;;
    esac > "$R/.claude/hooks/tests/$name.sh"
  done
}
runall() { bash "$R/.claude/hooks/tests/run-all.sh" 2>&1; }
last() { printf '%s\n' "$1" | tail -n 1; }

fresh test-a:gruen test-b:gruen
out="$(runall)"; rc=$?
[ "$rc" = 0 ] && ok || bad "alles grün endet mit 0 (rc=$rc)" "$out"
case "$out" in *"Alle Tests grün."*) ok ;; *) bad "alles grün heißt: Alle Tests grün." "$out" ;; esac
[ "$(last "$out")" = "Übersprungen: 0 Testdatei(en)." ] && ok || bad "letzte Zeile nennt 0 übersprungene" "$out"

fresh test-a:gruen test-b:skip test-c:skip
out="$(runall)"; rc=$?
[ "$rc" = 0 ] && ok || bad "Übersprungenes ist kein Fehler (rc=$rc)" "$out"
case "$out" in *"Alle Tests grün."*) bad "mit Übersprungenem steht nicht: Alle Tests grün." "$out" ;; *) ok ;; esac
case "$out" in *"übersprungen: test-b.sh, test-c.sh"*) ok ;; *) bad "Zusammenfassung nennt die übersprungenen Dateien" "$out" ;; esac
[ "$(last "$out")" = "Übersprungen: 2 Testdatei(en)." ] && ok || bad "letzte Zeile nennt 2 übersprungene" "$out"
case "$out" in *"Vergleich übersprungen"*) ok ;; *) bad "Ausgabe der Testdatei bleibt sichtbar" "$out" ;; esac

fresh test-a:rot test-b:skip
out="$(runall)"; rc=$?
[ "$rc" != 0 ] && ok || bad "rote Testdatei endet nicht mit 0"
case "$out" in *"1 Testdatei(en) mit Fehlern"*) ok ;; *) bad "rote Testdatei wird gezählt" "$out" ;; esac
[ "$(last "$out")" = "Übersprungen: 1 Testdatei(en)." ] && ok || bad "letzte Zeile auch bei Fehlern" "$out"

# Skill-Kopien: verglichen wird nur, wo beide Kopien liegen.
fresh test-a:gruen
mkdir -p "$R/.agents/skills/x"; echo eins > "$R/.agents/skills/x/SKILL.md"
out="$(runall)"
case "$out" in *"keine doppelten Kopien"*) ok ;; *) bad "nur .agents/skills: nichts zu vergleichen" "$out" ;; esac
mkdir -p "$R/.claude/skills/x"; echo eins > "$R/.claude/skills/x/SKILL.md"
out="$(runall)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"1 Paar(e) geprüft"*) true ;; *) false ;; esac && ok || bad "gleiche Kopien sind grün" "$out"
echo zwei > "$R/.claude/skills/x/SKILL.md"
out="$(runall)"; rc=$?
[ "$rc" != 0 ] && case "$out" in *"weicht von .claude/skills/x/SKILL.md ab"*) true ;; *) false ;; esac && ok ||
  bad "verschiedene Kopien sind rot" "$out"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
