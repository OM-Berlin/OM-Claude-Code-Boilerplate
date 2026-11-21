#!/usr/bin/env bash
# Tests für find-python.sh und für das Verhalten der Python-Hooks, wenn auf dem
# Rechner nur `python`, nur `py -3` oder gar kein brauchbares Python 3 da ist.
# Dafür bekommt jeder Fall einen eigenen, künstlichen PATH mit Attrappen. So lässt
# sich auch der Windows-Fall (python3-Platzhalter aus dem Store) auf jedem Rechner
# nachstellen. Lauf: bash .claude/hooks/tests/test-python-fallback.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STATE="$WORK/tmp/handoff-guard"
mkdir -p "$STATE"

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

# Das echte Python des Rechners, nur um die "funktioniert"-Attrappen zu bauen.
. "$HOOKS/find-python.sh"
if find_python; then
  REAL_BIN="$(command -v "${PY_CMD%% *}")"
  REAL_ARGS=""
  case "$PY_CMD" in *" "*) REAL_ARGS="${PY_CMD#* }" ;; esac
else
  REAL_BIN=""
fi

# Werkzeuge, die die Hooks außer Python brauchen. Alles andere (auch ein echtes
# python3 im System) ist im künstlichen PATH nicht sichtbar.
TOOLS="cat dirname sed grep find sort head basename date mkdir rm touch cut stat tr"
fakepy() { # fakepy <pfad> <art> [py]   Art: gut | store | py2 | fehlt
  case "$2" in
    gut)
      if [ "${3:-}" = py ]; then
        printf '#!/bin/sh\n[ "$1" = "-3" ] && shift\nexec "%s" %s "$@"\n' "$REAL_BIN" "$REAL_ARGS" > "$1"
      else
        printf '#!/bin/sh\nexec "%s" %s "$@"\n' "$REAL_BIN" "$REAL_ARGS" > "$1"
      fi ;;
    store) printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Store." >&2\nexit 49\n' > "$1" ;;
    py2)   printf '#!/bin/sh\nexit 1\n' > "$1" ;;
    *)     return 0 ;;
  esac
  chmod +x "$1"
}
newbin() { # newbin <name> <python3> <python> <py>
  local d="$WORK/bin-$1" t p
  mkdir -p "$d"
  for t in $TOOLS; do
    p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$d/$t"
  done
  fakepy "$d/python3" "$2"; fakepy "$d/python" "$3"; fakepy "$d/py" "$4" py
}

in_bin() { env PATH="$1" TMPDIR="$WORK/tmp" "$BASH" "${@:2}"; }

# find_case <name> <erwarteter PY_CMD> <python3> <python> <py>
find_case() {
  newbin "$1" "$3" "$4" "$5"
  local got
  got="$(in_bin "$WORK/bin-$1" -c ". '$HOOKS/find-python.sh'; find_python; echo \"[\$PY_CMD]\"")"
  [ "$got" = "[$2]" ] && ok || bad "$1: find_python soll '$2' wählen" "bekommen: $got"
}

# hooks_case <name> <aktiv 1/0>: arbeiten die beiden Python-Hooks (oder bleiben sie still)?
hooks_case() {
  local bin="$WORK/bin-$1" out rc err="$WORK/$1.err"
  rm -f "$STATE"/*
  out="$(printf '{"session_id":"fb","prompt":"lade den Handoff"}' | in_bin "$bin" "$HOOKS/handoff-offer-guard.sh" 2>"$err")"
  rc=$?
  [ "$rc" = 0 ] && ok || bad "$1: Prompt-Wächter muss mit 0 enden (rc=$rc)"
  if [ "$2" = 1 ]; then
    case "$out" in *"BRIEFING-MODUS"*) ok ;; *) bad "$1: Prompt-Wächter soll das Briefing melden" "$out" ;; esac
  else
    [ -z "$out" ] && [ ! -s "$err" ] && ok || bad "$1: Prompt-Wächter muss still bleiben" "$out $(cat "$err")"
  fi
  : > "$STATE/fb.briefing"
  printf '{"session_id":"fb","tool_name":"Write","tool_input":{"file_path":"x.txt"}}' \
    | in_bin "$bin" "$HOOKS/handoff-briefing-gate.sh" >/dev/null 2>"$err"
  rc=$?
  if [ "$2" = 1 ]; then
    [ "$rc" = 2 ] && ok || bad "$1: Schreibsperre soll Write sperren (rc=$rc)"
  else
    [ "$rc" = 0 ] && [ ! -s "$err" ] && ok || bad "$1: Schreibsperre muss still durchlassen (rc=$rc)" "$(cat "$err")"
  fi
}

if [ -n "$REAL_BIN" ]; then
  find_case nur-python3   python3 gut   fehlt fehlt;  hooks_case nur-python3 1
  find_case nur-python    python  fehlt gut   fehlt;  hooks_case nur-python 1
  find_case nur-py        "py -3" fehlt fehlt gut;    hooks_case nur-py 1
  # Windows: python3 ist der Store-Platzhalter, python.org-Python heißt python.
  find_case store-python  python  store gut   fehlt;  hooks_case store-python 1
  find_case store-py      "py -3" store store gut;    hooks_case store-py 1
  # python meldet sich als Python 2: überspringen und weitersuchen.
  find_case py2-py        "py -3" py2   py2   gut;    hooks_case py2-py 1
  find_case python3-vorn  python3 gut   gut   gut;   hooks_case python3-vorn 1
else
  echo "Hinweis: kein Python 3 auf diesem Rechner, die Fälle mit funktionierendem Python entfallen."
fi

# Kein brauchbares Python 3: Hooks bleiben still und enden mit 0.
find_case nichts       ""  fehlt fehlt fehlt;  hooks_case nichts 0
find_case alle-store   ""  store store store;  hooks_case alle-store 0
find_case nur-py2      ""  py2   py2   py2;    hooks_case nur-py2 0

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
