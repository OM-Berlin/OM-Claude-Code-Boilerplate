# =========================================================================
# einrichten.ps1 (Windows, PowerShell): macht aus dem Startpaket Ihr eigenes
# Projekt. Einmal ausführen:
#
#   powershell -ExecutionPolicy Bypass -File .\einrichten.ps1
#
# Tut dasselbe wie einrichten.sh, alles nur in diesem Ordner: .env.local anlegen,
# eigene Git-Geschichte beginnen, prüfen, dass .env.local nie hochgeladen wird und die
# Hooks mit ihren Tests prüfen (über Git Bash, wenn es installiert ist). Am Ende
# warnt es, wenn Ihr Claude Code für die Skills von Matt Pocock zu alt ist (vor 2.1.324).
# Globale Einstellungen auf Ihrem Rechner fasst das Skript nicht an.
# =========================================================================
$ErrorActionPreference = "Continue"  # Git schreibt Hinweise auf stderr, das soll nicht abbrechen
Set-Location -Path $PSScriptRoot
Write-Host "Projekt einrichten in: $PSScriptRoot"

# 1. .env.local
if (Test-Path ".env.local") {
    Write-Host "  [1/5] .env.local ist schon da und bleibt unverändert."
} else {
    Copy-Item ".env.example" ".env.local"
    Write-Host "  [1/5] .env.local angelegt. Echte Schlüssel tragen Sie nur dort ein."
}

# 2. Git vorhanden?
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  [2/5] Git fehlt. Bitte Git für Windows installieren und das Skript noch einmal starten."
    exit 1
}
Write-Host "  [2/5] Git ist installiert."

# 3. Eigene Git-Geschichte
function First-Commit($text) {
    git add -A
    git commit -q -m "chore: Projekt aus dem Startpaket angelegt" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [3/5] $text, erster Commit gemacht."
    } else {
        Write-Host "  [3/5] $text. Den ersten Commit hat Git abgelehnt, meist weil Git Ihren Namen"
        Write-Host "        noch nicht kennt. Nicht schlimm: Bitten Sie später Claude, Git für Sie"
        Write-Host "        einzurichten und den ersten Commit zu machen."
    }
}
# Eigene Arbeit heißt: Commits, die auf keinem Remote liegen, oder ungesicherte Änderungen.
function Eigene-Arbeit {
    if (git rev-list HEAD --not --remotes 2>$null) { return $true }
    if (git status --porcelain 2>$null) { return $true }
    return $false
}
$vorlage = ""
if (Test-Path ".git") { $vorlage = (git remote get-url origin 2>$null) }
if ((Test-Path ".git") -and ($vorlage -like "*OM-Claude-Code-Boilerplate*")) {
    if (Eigene-Arbeit) {
        Write-Host "  [3/5] Dieser Ordner hängt noch an der Vorlage, enthält aber schon Ihre eigenen"
        Write-Host "        Änderungen. Deshalb wird nichts gelöscht. Wenn Sie die Geschichte der Vorlage"
        Write-Host "        loswerden wollen: Sichern Sie Ihre Dateien, entpacken Sie das ZIP neu in einen"
        Write-Host "        leeren Ordner und kopieren Sie Ihre Dateien hinein. Oder bitten Sie Claude,"
        Write-Host "        den Verweis auf die Vorlage zu entfernen."
    } else {
        Remove-Item -Recurse -Force ".git"
        git init -q
        First-Commit "Geschichte der Vorlage entfernt, eigene begonnen"
    }
} elseif (Test-Path ".git") {
    Write-Host "  [3/5] Git-Geschichte ist schon Ihre eigene und bleibt."
} else {
    git init -q
    First-Commit "Git angelegt"
}

# 4. Schlüssel werden nie hochgeladen
git check-ignore -q .env.local
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [4/5] Geprüft: Git ignoriert .env.local."
} else {
    Write-Host "  [4/5] ACHTUNG: Git würde .env.local hochladen. Bitte .gitignore prüfen, bevor Sie etwas hochladen."
    exit 1
}

# 5. Hooks prüfen. Die Hook-Skripte und ihre Tests sind bash-Skripte und laufen über
# Git Bash. Gesucht wird absichtlich nur dort, wo Git für Windows es ablegt: Ein "bash"
# im PATH kann das von WSL sein, und das kommt mit Windows-Pfaden nicht zurecht.
function Find-GitBash {
    $kandidaten = @()
    foreach ($basis in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA "Programs"))) {
        if ($basis) { $kandidaten += (Join-Path $basis "Git\bin\bash.exe") }
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        # git.exe liegt in ...\Git\cmd oder ...\Git\bin, bash.exe in ...\Git\bin
        $kandidaten += (Join-Path (Split-Path (Split-Path $git.Source)) "bin\bash.exe")
    }
    foreach ($k in $kandidaten) {
        if ($k -and (Test-Path $k)) { return $k }
    }
    return $null
}
$bash = Find-GitBash
if (-not $bash) {
    Write-Host "  [5/5] Hook-Tests übersprungen, weil Git Bash nicht gefunden wurde. Installieren Sie Git für"
    Write-Host "        Windows (es bringt Git Bash mit); ohne Git Bash laufen auch die Hooks selbst nicht."
} else {
    & $bash -c '. .claude/hooks/find-python.sh 2>/dev/null && find_python' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [5/5] Hook-Tests übersprungen, weil Python 3 fehlt (gesucht: python3, python, py -3). Die Handoff-Hooks bleiben dann still."
    } else {
        & $bash .claude/hooks/tests/run-all.sh *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [5/5] Alle Hook-Tests grün (über Git Bash)."
        } else {
            Write-Host "  [5/5] Mindestens ein Hook-Test ist rot. Details: & '$bash' .claude/hooks/tests/run-all.sh"
        }
    }
}

# Hinweis: Der feste Stand der Skills von Matt Pocock (.claude/settings.json, Feld ref)
# braucht Claude Code ab 2.1.324. Bei einer älteren Version fehlt der Skill grilling.
# Die Desktop-App hat keinen Befehl claude und aktualisiert sich selbst: dann kein Hinweis.
$minClaude = [version]"2.1.324"
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $zeile = (claude --version 2>$null | Select-Object -First 1)
    $treffer = [regex]::Match("$zeile", '\d+\.\d+\.\d+')
    Write-Host ""
    if (-not $treffer.Success) {
        Write-Host "HINWEIS: Die Version von Claude Code ließ sich nicht lesen. Die Skills von Matt Pocock"
        Write-Host "(zum Beispiel grilling) brauchen Version $minClaude oder neuer. Geben Sie 'claude update'"
        Write-Host "ein und starten Sie Claude Code danach neu."
    } elseif ([version]$treffer.Value -lt $minClaude) {
        Write-Host "HINWEIS: Ihr Claude Code hat die Version $($treffer.Value). Die Skills von Matt Pocock"
        Write-Host "(zum Beispiel grilling) brauchen $minClaude oder neuer, sonst wird der Skill grilling nicht"
        Write-Host "angeboten. Geben Sie 'claude update' ein und starten Sie Claude Code danach neu."
    }
}

Write-Host ""
Write-Host "Fertig. Starten Sie jetzt 'claude' (oder 'codex') in diesem Ordner."
Write-Host "Die Hooks brauchen Git Bash, das mit Git für Windows kommt."
