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

# .gitattributes wirkt wie unter Git für Windows (core.autocrlf=true, die Vorgabe des
# Installers): Beim Einchecken keine Warnflut, beim Auschecken bleiben .sh und alle
# anderen Textdateien bei LF, nur .ps1 bekommt CRLF (Windows PowerShell 5.1).
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
GA="$WORK/ga"
mkdir -p "$GA/sub"
cp .gitattributes "$GA/"
printf 'echo a\necho b\n' > "$GA/sub/a.sh"
printf '{\n  "a": 1\n}\n' > "$GA/b.json"
printf '# Notiz\n\nText\n' > "$GA/c.md"
printf 'Write-Host "a"\r\nWrite-Host "b"\r\n' > "$GA/d.ps1"
lf_cr() { # lf_cr <datei>: "crlf", wenn ein Wagenrücklauf drinsteht, sonst "lf"
  if grep -q "$(printf '\r')" "$1"; then echo crlf; else echo lf; fi
}
(
  cd "$GA" && git init -q && git config core.autocrlf true &&
    git add -A 2>"$WORK/add.err" &&
    git -c user.name=T -c user.email=t@t.invalid commit -q -m t &&
    rm -f sub/a.sh b.json c.md d.ps1 && git checkout -q -- .
) || bad "Testrepo für .gitattributes ließ sich nicht anlegen" "$(cat "$WORK/add.err" 2>/dev/null)"
grep -q "will be replaced" "$WORK/add.err" && bad "git add warnt bei autocrlf=true über Zeilenenden" "$(head -3 "$WORK/add.err")" || ok
for f in sub/a.sh b.json c.md; do
  [ "$(lf_cr "$GA/$f")" = lf ] && ok || bad "$f bekommt bei autocrlf=true CRLF" "In .gitattributes fehlt '* text=auto eol=lf'."
done
[ "$(lf_cr "$GA/d.ps1")" = crlf ] && ok || bad ".ps1 muss CRLF bekommen" "In .gitattributes fehlt '*.ps1 text eol=crlf'."

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
else
  echo "Kein Git-Projekt, Prüfung der Ausführrechte übersprungen"
fi

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
