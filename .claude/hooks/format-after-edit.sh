#!/usr/bin/env bash
# PostToolUse-Hook: Formatiert eine Datei, nachdem Claude sie geschrieben oder
# geändert hat, aber nur, wenn das Projekt einen Formatierer mitbringt:
#
#   - Prettier, lokal installiert unter node_modules/.bin/prettier
#     (für .js .jsx .ts .tsx .css .scss .json .md .html .yaml .yml .vue .astro)
#   - Ruff, wenn ruff installiert ist und das Projekt eine pyproject.toml oder
#     ruff.toml hat (für .py)
#
# Ohne Formatierer tut der Hook nichts. Er lädt nie etwas aus dem Internet
# (kein npx), fasst nur Dateien im Projektordner an und endet immer mit Exitcode 0,
# damit eine Formatierung nie Claudes Arbeit stoppt.
#
# Warum ein Hook statt einer Regel: "Formatier jede Datei" als Satz in CLAUDE.md
# vergisst Claude manchmal, der Hook läuft nach jeder Änderung.
#
# Tests: bash .claude/hooks/tests/test-format-after-edit.sh
set -uo pipefail

payload="$(tr '\r\n' '  ')"
project="${CLAUDE_PROJECT_DIR:-$PWD}"

file="$(printf '%s' "$payload" |
  sed -E -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' |
  head -n 1 | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')"
[ -n "$file" ] || exit 0
case "$file" in /*) ;; *) file="$project/$file" ;; esac
[ -f "$file" ] || exit 0

# Nur Dateien im Projekt; Wege mit .. werden nicht formatiert.
case "$file" in
  *..*) exit 0 ;;
  "$project"/*) ;;
  *) exit 0 ;;
esac
case "$file" in */node_modules/* | */.git/*) exit 0 ;; esac

prettier="$project/node_modules/.bin/prettier"
case "$file" in
  *.js | *.jsx | *.ts | *.tsx | *.css | *.scss | *.json | *.md | *.html | *.yaml | *.yml | *.vue | *.astro)
    [ -x "$prettier" ] && (cd "$project" && "$prettier" --write --log-level warn "$file") >/dev/null 2>&1
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1 && { [ -f "$project/pyproject.toml" ] || [ -f "$project/ruff.toml" ]; }; then
      (cd "$project" && ruff format --quiet "$file") >/dev/null 2>&1
    fi
    ;;
esac
exit 0
