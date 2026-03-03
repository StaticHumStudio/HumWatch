#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs HumWatch as a background Windows service.

.DESCRIPTION
    Downloads NSSM (if not found), then registers HumWatch as an auto-start
    Windows service. The installer now hardens startup reliability by:
      - preferring a project-local venv Python
      - auto-creating the venv + dependencies when missing
      - enabling delayed auto-start for reboot stability
      - applying Windows Service recovery actions
      - running a local health check after service start

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
$RequirementsFile = Join-Path $ProjectRoot "requirements.txt"

Write-Host ""
Write-Host "HumWatch - Service Installer" -ForegroundColor Yellow
Write-Host "=============================" -ForegroundColor Yellow
Write-Host ""

# ── Helper: find or download NSSM ───────────────────────────────────────

function Get-Nssm {
    $local = Join-Path $ToolsDir "nssm.exe"
    if (Test-Path $local) { return $local }

    $onPath = Get-Command nssm -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

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

function Get-BootstrapPython {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $python) {
        throw "Python not found. Install Python 3.10+ and run setup.bat first."
    }

    $pythonPath = $python.Source
    if ($pythonPath -match "WindowsApps") {
        throw "Python resolves to WindowsApps alias ($pythonPath). Install real python.org Python and re-run setup.bat."
    }

    return $pythonPath
}

function Ensure-Venv {
    $venvPython = Join-Path $ProjectRoot "venv\Scripts\python.exe"
    if (Test-Path $venvPython) {
        Write-Host "[i] Python: $venvPython (venv)" -ForegroundColor Cyan
        return $venvPython
    }

    Write-Host "[!] venv not found. Creating one automatically..." -ForegroundColor Yellow
    $bootstrapPython = Get-BootstrapPython
    Write-Host "[i] Bootstrap Python: $bootstrapPython" -ForegroundColor Cyan

    & $bootstrapPython -m venv (Join-Path $ProjectRoot "venv")
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPython)) {
        throw "Failed to create venv. Run setup.bat and retry."
    }

    if (-not (Test-Path $RequirementsFile)) {
        throw "requirements.txt not found at $RequirementsFile"
    }

    Write-Host "[*] Installing dependencies into venv..." -ForegroundColor Yellow
    & $venvPython -m pip install --upgrade pip
    & $venvPython -m pip install -r $RequirementsFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Some dependencies failed to install." -ForegroundColor Yellow
        Write-Host "    HumWatch may still run in reduced mode (psutil-only)." -ForegroundColor Yellow
    }

    return $venvPython
}

function Wait-ForHealth {
    param(
        [int]$Port = 9100,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $url = "http://127.0.0.1:$Port/api/health"

    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 2
            if ($resp) {
                return $true
            }
        } catch {
            Start-Sleep -Milliseconds 750
        }
    }

    return $false
}

# ── Uninstall mode ──────────────────────────────────────────────────────

if ($Uninstall) {
    $Nssm = Get-Nssm
    & $Nssm status $ServiceName 2>&1 | Out-Null
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

# ── Find Python (prefer venv, create if missing) ───────────────────────

$PythonPath = Ensure-Venv

# ── Find or download NSSM ──────────────────────────────────────────────

$Nssm = Get-Nssm
Write-Host "[i] NSSM: $Nssm" -ForegroundColor Cyan

# ── Check for existing service ──────────────────────────────────────────

& $Nssm status $ServiceName 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[i] Service already installed. Reinstalling..." -ForegroundColor Yellow
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
& $Nssm set $ServiceName Start SERVICE_DELAYED_AUTO_START
& $Nssm set $ServiceName ObjectName LocalSystem
& $Nssm set $ServiceName AppEnvironmentExtra "PYTHONUNBUFFERED=1"

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

# Also configure Windows Service recovery (SCM-level)
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
sc.exe failureflag $ServiceName 1 | Out-Null

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
& $Nssm start $ServiceName | Out-Null

Start-Sleep -Seconds 3
$status = & $Nssm status $ServiceName
Write-Host ""
Write-Host "[+] HumWatch service: $status" -ForegroundColor Green

$healthy = Wait-ForHealth -Port 9100 -TimeoutSeconds 30
if ($healthy) {
    Write-Host "[+] Health check passed: http://127.0.0.1:9100/api/health" -ForegroundColor Green
} else {
    Write-Host "[!] Health check timed out. Service may still be warming up, or startup failed." -ForegroundColor Red
    Write-Host "    Check logs:" -ForegroundColor Yellow
    Write-Host "      $StdoutLog" -ForegroundColor Yellow
    Write-Host "      $StderrLog" -ForegroundColor Yellow
    if (Test-Path $StderrLog) {
        Write-Host "" 
        Write-Host "--- Last 40 lines of stderr ---" -ForegroundColor Yellow
        Get-Content $StderrLog -Tail 40
        Write-Host "--- End stderr ---" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  Dashboard:  http://localhost:9100" -ForegroundColor Cyan
Write-Host "  Logs:       $LogDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "  The service runs in the background and starts" -ForegroundColor White
Write-Host "  automatically on every reboot (delayed auto-start)." -ForegroundColor White
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
