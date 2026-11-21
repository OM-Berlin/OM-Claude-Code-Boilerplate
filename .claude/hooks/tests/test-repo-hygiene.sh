#!/usr/bin/env bash
# Prüft, dass die Shell-Skripte auf jedem Rechner laufen: Zeilenenden LF (sonst
# scheitern sie unter Windows mit "\r: command not found") und ausführbar in Git.
# Lauf: bash .claude/hooks/tests/test-repo-hygiene.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 1

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

grep -qE '^\*\.sh[[:space:]]+text[[:space:]]+eol=lf' .gitattributes 2>/dev/null \
  && ok || bad ".gitattributes muss '*.sh text eol=lf' enthalten" "Sonst bekommen die Skripte unter Windows CRLF-Zeilenenden."

scripts="$(find . \( -name .git -o -name node_modules -o -name dist \) -prune -o -type f -name '*.sh' -print | sort)"
[ -n "$scripts" ] && ok || bad "keine .sh-Dateien gefunden"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -q "$(printf '\r')" "$f"; then
    bad "$f hat CRLF-Zeilenenden" "Mit 'sed -i.bak \"s/\\r\$//\" $f' (oder im Editor auf LF umstellen) beheben."
  else
    ok
  fi
done <<EOF
$scripts
EOF

# Dateirechte gibt es nur in einem Git-Projekt; im entpackten Startpaket ohne .git entfällt der Teil.
if git rev-parse --git-dir >/dev/null 2>&1; then
  while read -r mode _ _ f; do
    [ -n "$f" ] || continue
    [ "$mode" = 100755 ] && ok || bad "$f ist in Git nicht ausführbar ($mode)" "Beheben: git update-index --chmod=+x $f"
  done <<EOF
$(git ls-files -s -- '*.sh')
EOF
fi

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
