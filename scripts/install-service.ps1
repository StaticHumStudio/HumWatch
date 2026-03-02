#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs HumWatch as a background Windows service.

.DESCRIPTION
    Downloads NSSM (if not found), then registers HumWatch as an auto-start
    Windows service running under the SYSTEM account. The service starts on
    boot, runs in the background (no console window), and auto-restarts on
    failure. Logs are rotated at 5 MB.

.PARAMETER Uninstall
    Stop and remove the HumWatch service.

.NOTES
    Run as Administrator:
        powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1
#>

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$ServiceName = "HumWatch"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ToolsDir = Join-Path $ProjectRoot "tools"
$LogDir = Join-Path $ProjectRoot "logs"

Write-Host ""
Write-Host "HumWatch - Service Installer" -ForegroundColor Yellow
Write-Host "=============================" -ForegroundColor Yellow
Write-Host ""

# ── Helper: find or download NSSM ───────────────────────────────────────

function Get-Nssm {
    # Check tools/ first
    $local = Join-Path $ToolsDir "nssm.exe"
    if (Test-Path $local) { return $local }

    # Check PATH
    $onPath = Get-Command nssm -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    # Auto-download
    Write-Host "[*] Downloading NSSM (Non-Sucking Service Manager)..." -ForegroundColor Yellow
    if (-not (Test-Path $ToolsDir)) {
        New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
    }

    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
    $zipPath = Join-Path $env:TEMP "nssm.zip"
    $extractPath = Join-Path $env:TEMP "nssm-extract"

    try {
        $ProgressPreference = "SilentlyContinue"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $nssmUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        # Find the 64-bit binary
        $bin = Get-ChildItem -Path $extractPath -Recurse -Filter "nssm.exe" |
            Where-Object { $_.DirectoryName -match "win64" } |
            Select-Object -First 1
        if (-not $bin) {
            $bin = Get-ChildItem -Path $extractPath -Recurse -Filter "nssm.exe" |
                Select-Object -First 1
        }
        if (-not $bin) {
            throw "nssm.exe not found in downloaded archive"
        }

        Copy-Item $bin.FullName $local -Force
        Write-Host "[+] NSSM saved to tools/nssm.exe" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Failed to download NSSM: $_" -ForegroundColor Red
        Write-Host "    Download manually from: https://nssm.cc/download" -ForegroundColor Cyan
        exit 1
    }
    finally {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $local
}

# ── Uninstall mode ──────────────────────────────────────────────────────

if ($Uninstall) {
    $Nssm = Get-Nssm
    $status = & $Nssm status $ServiceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[i] Service '$ServiceName' is not installed." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "[*] Stopping service..." -ForegroundColor Yellow
    & $Nssm stop $ServiceName 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "[*] Removing service..." -ForegroundColor Yellow
    & $Nssm remove $ServiceName confirm
    Write-Host "[+] Service removed." -ForegroundColor Green
    exit 0
}

# ── Find Python ─────────────────────────────────────────────────────────

$VenvPython = Join-Path $ProjectRoot "venv\Scripts\python.exe"
if (Test-Path $VenvPython) {
    $PythonPath = $VenvPython
    Write-Host "[i] Python: $PythonPath (venv)" -ForegroundColor Cyan
} else {
    $Python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $Python) { $Python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $Python) {
        Write-Host "[!] Python not found. Run setup.bat first." -ForegroundColor Red
        exit 1
    }
    $PythonPath = $Python.Source
    Write-Host "[i] Python: $PythonPath (system)" -ForegroundColor Cyan
    Write-Host "[!] No venv found. Consider running setup.bat first." -ForegroundColor Yellow
}

# ── Find or download NSSM ──────────────────────────────────────────────

$Nssm = Get-Nssm
Write-Host "[i] NSSM: $Nssm" -ForegroundColor Cyan

# ── Check for existing service ──────────────────────────────────────────

$existing = & $Nssm status $ServiceName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[i] Service already installed (status: $existing). Reinstalling..." -ForegroundColor Yellow
    & $Nssm stop $ServiceName 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    & $Nssm remove $ServiceName confirm
}

# ── Create log directory ────────────────────────────────────────────────

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ── Install service ─────────────────────────────────────────────────────

Write-Host "[*] Installing service..." -ForegroundColor Yellow
& $Nssm install $ServiceName $PythonPath "-m" "agent.main"
& $Nssm set $ServiceName AppDirectory $ProjectRoot
& $Nssm set $ServiceName DisplayName "HumWatch Agent"
& $Nssm set $ServiceName Description "Local hardware monitoring agent - Static Hum Studio"
& $Nssm set $ServiceName Start SERVICE_AUTO_START
& $Nssm set $ServiceName ObjectName LocalSystem

# Log rotation (5 MB per file)
$StdoutLog = Join-Path $LogDir "humwatch-stdout.log"
$StderrLog = Join-Path $LogDir "humwatch-stderr.log"
& $Nssm set $ServiceName AppStdout $StdoutLog
& $Nssm set $ServiceName AppStderr $StderrLog
& $Nssm set $ServiceName AppStdoutCreationDisposition 4
& $Nssm set $ServiceName AppStderrCreationDisposition 4
& $Nssm set $ServiceName AppRotateFiles 1
& $Nssm set $ServiceName AppRotateOnline 1
& $Nssm set $ServiceName AppRotateBytes 5242880

# Auto-restart on failure (5 second delay)
& $Nssm set $ServiceName AppExit Default Restart
& $Nssm set $ServiceName AppRestartDelay 5000

Write-Host "[+] Service installed" -ForegroundColor Green

# ── Pre-flight verification ────────────────────────────────────────────

Write-Host ""
Write-Host "[*] Running pre-flight verification..." -ForegroundColor Yellow
& $PythonPath -m agent.verify
$verifyExit = $LASTEXITCODE
if ($verifyExit -eq 2) {
    Write-Host ""
    Write-Host "[!] Verification found errors. Service may not work correctly." -ForegroundColor Red
    Write-Host "    Fix the issues above, then restart: nssm restart $ServiceName" -ForegroundColor Yellow
    Write-Host ""
}

# ── Start service ───────────────────────────────────────────────────────

Write-Host "[*] Starting service..." -ForegroundColor Yellow
& $Nssm start $ServiceName

Start-Sleep -Seconds 3
$status = & $Nssm status $ServiceName
Write-Host ""
Write-Host "[+] HumWatch service: $status" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard:  http://localhost:9100" -ForegroundColor Cyan
Write-Host "  Logs:       $LogDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "  The service runs in the background and starts" -ForegroundColor White
Write-Host "  automatically on every reboot. No console window." -ForegroundColor White
Write-Host ""
Write-Host "  Manage:" -ForegroundColor Yellow
Write-Host "    nssm status $ServiceName" -ForegroundColor White
Write-Host "    nssm stop $ServiceName" -ForegroundColor White
Write-Host "    nssm start $ServiceName" -ForegroundColor White
Write-Host "    nssm restart $ServiceName" -ForegroundColor White
Write-Host ""
Write-Host "  Uninstall:" -ForegroundColor Yellow
Write-Host "    powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1 -Uninstall" -ForegroundColor White
Write-Host ""
