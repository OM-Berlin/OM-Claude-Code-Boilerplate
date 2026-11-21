#!/usr/bin/env bash
# =========================================================================
# einrichten.sh: macht aus dem Startpaket Ihr eigenes Projekt. Einmal ausführen:
#
#   bash einrichten.sh
#
# Was passiert, alles nur in diesem Ordner:
#   1. .env.local wird aus .env.example angelegt (echte Schlüssel nur dorthin)
#   2. die Hook-Skripte werden ausführbar gemacht
#   3. Git beginnt eine eigene Geschichte für dieses Projekt (erster Commit)
#   4. es wird geprüft, dass .env.local nie hochgeladen wird
#   5. die Hooks werden mit ihren Tests geprüft (wenn Python 3 da ist)
#
# Globale Einstellungen auf Ihrem Rechner fasst das Skript nicht an.
# Läuft gefahrlos mehrfach: Vorhandenes wird nicht überschrieben.
# =========================================================================
set -uo pipefail
cd "$(dirname "$0")" || exit 1

echo "Projekt einrichten in: $(pwd)"

# 1. .env.local
if [ -f .env.local ]; then
  echo "  [1/5] .env.local ist schon da und bleibt unverändert."
else
  cp .env.example .env.local
  echo "  [1/5] .env.local angelegt. Echte Schlüssel tragen Sie nur dort ein."
fi

# 2. Hooks ausführbar
chmod +x .claude/hooks/*.sh .claude/hooks/tests/*.sh 2>/dev/null
echo "  [2/5] Hook-Skripte sind ausführbar."

# 3. Eigene Git-Geschichte
if ! command -v git >/dev/null 2>&1; then
  echo "  [3/5] Git fehlt. Bitte Git installieren und das Skript noch einmal starten."
  exit 1
fi
first_commit() {
  git add -A
  if git commit -q -m "chore: Projekt aus dem Startpaket angelegt" 2>/dev/null; then
    echo "  [3/5] $1, erster Commit gemacht."
  else
    echo "  [3/5] $1. Den ersten Commit hat Git abgelehnt, meist weil Git Ihren Namen"
    echo "        noch nicht kennt. Nicht schlimm: Bitten Sie später Claude, Git für Sie"
    echo "        einzurichten und den ersten Commit zu machen."
  fi
}
# Eigene Arbeit heißt: Commits, die auf keinem Remote liegen, oder ungesicherte Änderungen.
eigene_arbeit() {
  [ -n "$(git rev-list HEAD --not --remotes 2>/dev/null)" ] && return 0
  [ -n "$(git status --porcelain 2>/dev/null)" ] && return 0
  return 1
}
vorlage="$(git remote get-url origin 2>/dev/null || true)"
if [ -d .git ] && printf '%s' "$vorlage" | grep -q 'OM-Claude-Code-Boilerplate'; then
  if eigene_arbeit; then
    echo "  [3/5] Dieser Ordner hängt noch an der Vorlage, enthält aber schon Ihre eigenen"
    echo "        Änderungen. Deshalb wird nichts gelöscht. Wenn Sie die Geschichte der Vorlage"
    echo "        loswerden wollen: Sichern Sie Ihre Dateien, entpacken Sie das ZIP neu in einen"
    echo "        leeren Ordner und kopieren Sie Ihre Dateien hinein. Oder bitten Sie Claude,"
    echo "        den Verweis auf die Vorlage zu entfernen."
  else
    rm -rf .git
    git init -q
    first_commit "Geschichte der Vorlage entfernt, eigene begonnen"
  fi
elif [ -d .git ]; then
  echo "  [3/5] Git-Geschichte ist schon Ihre eigene und bleibt."
else
  git init -q
  first_commit "Git angelegt"
fi

# 4. Schlüssel werden nie hochgeladen
if git check-ignore -q .env.local; then
  echo "  [4/5] Geprüft: Git ignoriert .env.local."
else
  echo "  [4/5] ACHTUNG: Git würde .env.local hochladen. Bitte .gitignore prüfen, bevor Sie etwas hochladen."
  exit 1
fi

# 5. Hooks prüfen
if [ -n "${EINRICHTEN_SKIP_HOOKTESTS:-}" ]; then
  echo "  [5/5] Hook-Tests übersprungen (nur für die Tests dieses Skripts)."
elif . .claude/hooks/find-python.sh 2>/dev/null && find_python; then
  if bash .claude/hooks/tests/run-all.sh >/dev/null 2>&1; then
    echo "  [5/5] Alle Hook-Tests grün."
  else
    echo "  [5/5] Mindestens ein Hook-Test ist rot. Details: bash .claude/hooks/tests/run-all.sh"
  fi
else
  echo "  [5/5] Hook-Tests übersprungen, weil Python 3 fehlt (gesucht: python3, python, py -3). Die Handoff-Hooks bleiben dann still."
fi

echo
echo "Fertig. Starten Sie jetzt 'claude' (oder 'codex') in diesem Ordner."
