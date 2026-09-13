#!/usr/bin/env bash
# =========================================================================
# Einrichten — macht aus dem Klon ein eigenes Projekt. Einmal ausführen:
#
#   bash einrichten.sh
#
# Was passiert:
#   1. .env.local wird aus .env.example angelegt (echte Schlüssel gehören nur dorthin)
#   2. die Hook-Skripte werden ausführbar gemacht
#   3. die Git-Geschichte der Vorlage wird durch eine eigene ersetzt (erster Commit)
#   4. es wird geprüft, dass .env.local wirklich ignoriert wird
#
# Läuft gefahrlos mehrfach: Vorhandenes wird nicht überschrieben.
# =========================================================================
set -uo pipefail
cd "$(dirname "$0")" || exit 1

echo "→ Projekt einrichten in: $(pwd)"

# 1. .env.local
if [ -f .env.local ]; then
  echo "   .env.local ist schon da, bleibt unverändert."
else
  cp .env.example .env.local
  echo "   .env.local aus .env.example angelegt. Echte Werte nur dort eintragen."
fi

# 2. Hooks ausführbar
chmod +x .claude/hooks/*.sh .codex/hooks/*.sh 2>/dev/null
echo "   Hook-Skripte ausführbar gemacht."

# 3. Eigene Git-Geschichte
if ! command -v git >/dev/null 2>&1; then
  echo "   Git fehlt. Erst Git installieren (siehe Setup-Checkliste), dann noch einmal ausführen."
  exit 1
fi
vorlage="$(git remote get-url origin 2>/dev/null || true)"
if [ -d .git ] && printf '%s' "$vorlage" | grep -q 'OM-Claude-Code-Boilerplate'; then
  rm -rf .git
  git init -q
  git add -A
  git commit -q -m "chore: Projekt aus der Kurs-Boilerplate angelegt"
  echo "   Eigene Git-Geschichte begonnen (erster Commit)."
elif [ -d .git ]; then
  echo "   Git-Geschichte ist schon eigene, bleibt."
else
  git init -q
  git add -A
  git commit -q -m "chore: Projekt aus der Kurs-Boilerplate angelegt"
  echo "   Git angelegt, erster Commit gemacht."
fi

# 4. Prüfen, dass Schlüssel nicht hochgeladen würden
if git check-ignore -q .env.local; then
  echo "   Geprüft: .env.local wird von Git ignoriert."
else
  echo "   ACHTUNG: .env.local wird NICHT ignoriert. .gitignore prüfen, bevor etwas hochgeladen wird."
  exit 1
fi

echo
echo "Fertig. Jetzt: die erste Zeile in CLAUDE.md ersetzen, dann 'claude' oder 'codex' starten."
