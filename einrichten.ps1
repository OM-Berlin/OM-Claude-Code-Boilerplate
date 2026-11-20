# =========================================================================
# einrichten.ps1 (Windows, PowerShell): macht aus dem Startpaket Ihr eigenes
# Projekt. Einmal ausführen:
#
#   powershell -ExecutionPolicy Bypass -File .\einrichten.ps1
#
# Tut dasselbe wie einrichten.sh, alles nur in diesem Ordner: .env.local anlegen,
# eigene Git-Geschichte beginnen, prüfen, dass .env.local nie hochgeladen wird.
# Globale Einstellungen auf Ihrem Rechner fasst das Skript nicht an.
# =========================================================================
$ErrorActionPreference = "Continue"  # Git schreibt Hinweise auf stderr, das soll nicht abbrechen
Set-Location -Path $PSScriptRoot
Write-Host "Projekt einrichten in: $PSScriptRoot"

# 1. .env.local
if (Test-Path ".env.local") {
    Write-Host "  [1/4] .env.local ist schon da und bleibt unverändert."
} else {
    Copy-Item ".env.example" ".env.local"
    Write-Host "  [1/4] .env.local angelegt. Echte Schlüssel tragen Sie nur dort ein."
}

# 2. Git vorhanden?
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  [2/4] Git fehlt. Bitte Git für Windows installieren und das Skript noch einmal starten."
    exit 1
}
Write-Host "  [2/4] Git ist installiert."

# 3. Eigene Git-Geschichte
function First-Commit($text) {
    git add -A
    git commit -q -m "chore: Projekt aus dem Startpaket angelegt" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [3/4] $text, erster Commit gemacht."
    } else {
        Write-Host "  [3/4] $text. Den ersten Commit hat Git abgelehnt, meist weil Git Ihren Namen"
        Write-Host "        noch nicht kennt. Nicht schlimm: Bitten Sie später Claude, Git für Sie"
        Write-Host "        einzurichten und den ersten Commit zu machen."
    }
}
$vorlage = ""
if (Test-Path ".git") { $vorlage = (git remote get-url origin 2>$null) }
if ((Test-Path ".git") -and ($vorlage -like "*OM-Claude-Code-Boilerplate*")) {
    Remove-Item -Recurse -Force ".git"
    git init -q
    First-Commit "Geschichte der Vorlage entfernt, eigene begonnen"
} elseif (Test-Path ".git") {
    Write-Host "  [3/4] Git-Geschichte ist schon Ihre eigene und bleibt."
} else {
    git init -q
    First-Commit "Git angelegt"
}

# 4. Schlüssel werden nie hochgeladen
git check-ignore -q .env.local
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [4/4] Geprüft: Git ignoriert .env.local."
} else {
    Write-Host "  [4/4] ACHTUNG: Git würde .env.local hochladen. Bitte .gitignore prüfen, bevor Sie etwas hochladen."
    exit 1
}

Write-Host ""
Write-Host "Fertig. Starten Sie jetzt 'claude' (oder 'codex') in diesem Ordner."
Write-Host "Die Hooks brauchen Git Bash, das mit Git für Windows kommt."
