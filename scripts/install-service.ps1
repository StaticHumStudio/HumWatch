#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs HumWatch as a Windows service using NSSM.

.DESCRIPTION
    Downloads NSSM (if not found) and registers HumWatch as an auto-start
    Windows service running under the SYSTEM account.

.PARAMETER NssmPath
    Path to nssm.exe. If not provided, checks PATH and offers to download.

.NOTES
    Run as Administrator:
        powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1
#>

param(
    [string]$NssmPath = ""
)

$ErrorActionPreference = "Stop"

$ServiceName = "HumWatch"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LogDir = Join-Path $ProjectRoot "logs"

Write-Host "HumWatch — Service Installer" -ForegroundColor Yellow
Write-Host "=============================" -ForegroundColor Yellow
Write-Host ""

# Find Python — prefer venv if available
$VenvPython = Join-Path $ProjectRoot "venv\Scripts\python.exe"
if (Test-Path $VenvPython) {
    $PythonPath = $VenvPython
    Write-Host "[i] Python: $PythonPath (venv)" -ForegroundColor Cyan
} else {
    $Python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $Python) {
        $Python = Get-Command python -ErrorAction SilentlyContinue
    }
    if (-not $Python) {
        Write-Host "[!] Python not found. Run setup.bat first, or install Python 3.10+." -ForegroundColor Red
        exit 1
    }
    $PythonPath = $Python.Source
    Write-Host "[i] Python: $PythonPath (system)" -ForegroundColor Cyan
    Write-Host "[!] No venv found. Consider running setup.bat first." -ForegroundColor Yellow
}

# Find or download NSSM
if ($NssmPath -and (Test-Path $NssmPath)) {
    $Nssm = $NssmPath
} else {
    $Nssm = Get-Command nssm -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

if (-not $Nssm) {
    Write-Host "[!] NSSM not found on PATH." -ForegroundColor Yellow
    Write-Host "    Download from: https://nssm.cc/download" -ForegroundColor Cyan
    Write-Host "    Or install via: winget install nssm" -ForegroundColor Cyan
    exit 1
}
Write-Host "[i] NSSM: $Nssm" -ForegroundColor Cyan

# Check if service already exists
$existing = & $Nssm status $ServiceName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[i] Service '$ServiceName' already exists (status: $existing)" -ForegroundColor Yellow
    $response = Read-Host "    Remove and reinstall? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        exit 0
    }
    Write-Host "[*] Stopping and removing existing service..." -ForegroundColor Yellow
    & $Nssm stop $ServiceName 2>&1 | Out-Null
    & $Nssm remove $ServiceName confirm
}

# Create log directory
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Install service
Write-Host "[*] Installing service..." -ForegroundColor Yellow
& $Nssm install $ServiceName $PythonPath "-m" "agent.main"
& $Nssm set $ServiceName AppDirectory $ProjectRoot
& $Nssm set $ServiceName DisplayName "HumWatch Agent"
& $Nssm set $ServiceName Description "Local hardware monitoring agent — Static Hum Studio"
& $Nssm set $ServiceName Start SERVICE_AUTO_START
& $Nssm set $ServiceName ObjectName LocalSystem

# Log rotation
$StdoutLog = Join-Path $LogDir "humwatch-stdout.log"
$StderrLog = Join-Path $LogDir "humwatch-stderr.log"
& $Nssm set $ServiceName AppStdout $StdoutLog
& $Nssm set $ServiceName AppStderr $StderrLog
& $Nssm set $ServiceName AppStdoutCreationDisposition 4
& $Nssm set $ServiceName AppStderrCreationDisposition 4
& $Nssm set $ServiceName AppRotateFiles 1
& $Nssm set $ServiceName AppRotateOnline 1
& $Nssm set $ServiceName AppRotateBytes 5242880

# Restart on failure
& $Nssm set $ServiceName AppExit Default Restart
& $Nssm set $ServiceName AppRestartDelay 5000

Write-Host "[+] Service installed" -ForegroundColor Green

# Start service
Write-Host "[*] Starting service..." -ForegroundColor Yellow
& $Nssm start $ServiceName

Start-Sleep -Seconds 2
$status = & $Nssm status $ServiceName
Write-Host ""
Write-Host "[+] HumWatch service status: $status" -ForegroundColor Green
Write-Host "[i] Dashboard: http://localhost:9100" -ForegroundColor Cyan
Write-Host "[i] Logs: $LogDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "Manage with:" -ForegroundColor Yellow
Write-Host "    nssm status $ServiceName" -ForegroundColor White
Write-Host "    nssm stop $ServiceName" -ForegroundColor White
Write-Host "    nssm start $ServiceName" -ForegroundColor White
Write-Host "    nssm restart $ServiceName" -ForegroundColor White
