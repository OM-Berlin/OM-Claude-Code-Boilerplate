#!/usr/bin/env bash
# Hilfsdatei für die Hooks: sucht einen funktionierenden Python-3-Interpreter.
# Sie wird mit `. find-python.sh` geladen und stellt die Funktion find_python bereit.
#
# Warum drei Namen: Unter macOS und Linux heißt Python 3 meist `python3`. Das
# Windows-Installationsprogramm von python.org legt dagegen oft nur `python` und
# den Starter `py` an. Außerdem gibt es dort einen `python3`-Platzhalter aus dem
# Microsoft Store, der existiert, aber nur auf den Store verweist. Deshalb zählt
# ein Name erst, wenn der Interpreter wirklich läuft und sich als Python 3 meldet.
#
# find_python setzt PY_CMD (zum Beispiel "python3" oder "py -3") und gibt 0 zurück.
# Findet es nichts, bleibt PY_CMD leer und der Rückgabewert ist 1. Aufruf immer
# ohne Anführungszeichen: $PY_CMD -c '...' (bei "py -3" sind das zwei Wörter).
#
# Tests: bash .claude/hooks/tests/test-python-fallback.sh
# bash 3.2 kompatibel (macOS).
find_python() {
  PY_CMD=""
  local candidate
  for candidate in "python3" "python" "py -3"; do
    # Absichtlich ohne Anführungszeichen: "py -3" muss in zwei Wörter zerfallen.
    if $candidate -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1 </dev/null; then
      PY_CMD="$candidate"
      return 0
    fi
  done
  return 1
}
