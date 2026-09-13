# =========================================================================
# Einrichten (Windows, PowerShell) — macht aus dem Klon ein eigenes Projekt:
#
#   powershell -ExecutionPolicy Bypass -File .\einrichten.ps1
#
# Tut dasselbe wie einrichten.sh: .env.local anlegen, eigene Git-Geschichte,
# prüfen, dass .env.local ignoriert wird. Läuft gefahrlos mehrfach.
# =========================================================================
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot
Write-Host "→ Projekt einrichten in: $PSScriptRoot"

# 1. .env.local
if (Test-Path ".env.local") {
    Write-Host "   .env.local ist schon da, bleibt unverändert."
} else {
    Copy-Item ".env.example" ".env.local"
    Write-Host "   .env.local aus .env.example angelegt. Echte Werte nur dort eintragen."
}

# 2. Git vorhanden?
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "   Git fehlt. Erst Git installieren (siehe Setup-Checkliste), dann noch einmal ausführen."
    exit 1
}

# 3. Eigene Git-Geschichte
$vorlage = ""
if (Test-Path ".git") { $vorlage = (git remote get-url origin 2>$null) }
if ((Test-Path ".git") -and ($vorlage -like "*OM-Claude-Code-Boilerplate*")) {
    Remove-Item -Recurse -Force ".git"
    git init -q
    git add -A
    git commit -q -m "chore: Projekt aus der Kurs-Boilerplate angelegt"
    Write-Host "   Eigene Git-Geschichte begonnen (erster Commit)."
} elseif (Test-Path ".git") {
    Write-Host "   Git-Geschichte ist schon eigene, bleibt."
} else {
    git init -q
    git add -A
    git commit -q -m "chore: Projekt aus der Kurs-Boilerplate angelegt"
    Write-Host "   Git angelegt, erster Commit gemacht."
}

# 4. Prüfen, dass Schlüssel nicht hochgeladen würden
git check-ignore -q .env.local
if ($LASTEXITCODE -eq 0) {
    Write-Host "   Geprüft: .env.local wird von Git ignoriert."
} else {
    Write-Host "   ACHTUNG: .env.local wird NICHT ignoriert. .gitignore prüfen, bevor etwas hochgeladen wird."
    exit 1
}

Write-Host ""
Write-Host "Fertig. Jetzt: die erste Zeile in CLAUDE.md ersetzen, dann 'claude' oder 'codex' starten."
