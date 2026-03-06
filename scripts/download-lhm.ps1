<#
.SYNOPSIS
    Downloads LibreHardwareMonitor DLLs required by HumWatch.

.DESCRIPTION
    Fetches LibreHardwareMonitorLib.dll and HidSharp.dll from the official
    LibreHardwareMonitor GitHub releases and places them in the lib/ directory.
    No admin privileges required for downloading -- admin is only needed at
    runtime for hardware sensor access.

.NOTES
    Run once after cloning the repo:
        powershell -ExecutionPolicy Bypass -File scripts\download-lhm.ps1
#>

$ErrorActionPreference = "Stop"

$LHM_VERSION = "0.9.6"
$RELEASE_URL = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v${LHM_VERSION}/LibreHardwareMonitor.zip"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LibDir = Join-Path $ProjectRoot "lib"
$TempZip = Join-Path $env:TEMP "lhm-${LHM_VERSION}.zip"
$TempExtract = Join-Path $env:TEMP "lhm-extract"

Write-Host "HumWatch - LibreHardwareMonitor Downloader" -ForegroundColor Yellow
Write-Host "==========================================="
Write-Host ""

# --- PawnIO driver (replaces WinRing0, required by LHM v0.9.5+) ---
Write-Host "[*] Checking for PawnIO driver..." -ForegroundColor Yellow
$pawnInstalled = $false
try {
    $wingetList = winget list --id PawnIO.PawnIO 2>&1
    if ($wingetList -match "PawnIO") {
        $pawnInstalled = $true
    }
} catch {}

if ($pawnInstalled) {
    Write-Host "[+] PawnIO is already installed" -ForegroundColor Green
} else {
    Write-Host "[*] Installing PawnIO driver (replaces deprecated WinRing0)..." -ForegroundColor Yellow
    try {
        winget install PawnIO.PawnIO --accept-source-agreements --accept-package-agreements
        Write-Host "[+] PawnIO installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "[!] PawnIO installation failed: $_" -ForegroundColor Red
        Write-Host "    Install manually: winget install PawnIO.PawnIO" -ForegroundColor Yellow
        Write-Host "    HumWatch will still work in psutil-only mode without it." -ForegroundColor Yellow
    }
}
Write-Host ""

# Create lib directory
if (-not (Test-Path $LibDir)) {
    New-Item -ItemType Directory -Path $LibDir -Force | Out-Null
    Write-Host "[+] Created lib/ directory" -ForegroundColor Green
}

# Check if already downloaded
$DllPath = Join-Path $LibDir "LibreHardwareMonitorLib.dll"
if (Test-Path $DllPath) {
    Write-Host "[i] LibreHardwareMonitorLib.dll already exists in lib/" -ForegroundColor Cyan
    $response = Read-Host "    Overwrite? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "[i] Skipped. Existing files kept." -ForegroundColor Cyan
        exit 0
    }
}

# Download release zip (with fallback methods)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$downloaded = $false

Write-Host "[*] Downloading LHM v${LHM_VERSION} (Invoke-WebRequest)..." -ForegroundColor Yellow
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $RELEASE_URL -OutFile $TempZip -UseBasicParsing -TimeoutSec 60
    $downloaded = $true
    Write-Host "[+] Download complete" -ForegroundColor Green
} catch {
    Write-Host "[!] Invoke-WebRequest failed: $_" -ForegroundColor Yellow
}

if (-not $downloaded) {
    Write-Host "[*] Retrying with WebClient..." -ForegroundColor Yellow
    try {
        (New-Object System.Net.WebClient).DownloadFile($RELEASE_URL, $TempZip)
        $downloaded = $true
        Write-Host "[+] Download complete" -ForegroundColor Green
    } catch {
        Write-Host "[!] WebClient failed: $_" -ForegroundColor Yellow
    }
}

if (-not $downloaded) {
    Write-Host "[*] Retrying with curl..." -ForegroundColor Yellow
    try {
        curl.exe -sL -o $TempZip $RELEASE_URL --connect-timeout 30
        if (Test-Path $TempZip) { $downloaded = $true; Write-Host "[+] Download complete" -ForegroundColor Green }
    } catch {
        Write-Host "[!] curl failed: $_" -ForegroundColor Yellow
    }
}

if (-not $downloaded) {
    Write-Host "[!] All download methods failed." -ForegroundColor Red
    Write-Host "    You can manually download from:" -ForegroundColor Yellow
    Write-Host "    $RELEASE_URL" -ForegroundColor Cyan
    exit 1
}

# Verify the zip isn't corrupt/truncated
$zipSize = (Get-Item $TempZip).Length
if ($zipSize -lt 100000) {
    Write-Host "[!] Downloaded file is too small ($([int]($zipSize/1KB)) KB) -- may be corrupt or blocked." -ForegroundColor Red
    Write-Host "    You can manually download from:" -ForegroundColor Yellow
    Write-Host "    $RELEASE_URL" -ForegroundColor Cyan
    Remove-Item $TempZip -Force -ErrorAction SilentlyContinue
    exit 1
}

# Extract
Write-Host "[*] Extracting..." -ForegroundColor Yellow
if (Test-Path $TempExtract) {
    Remove-Item $TempExtract -Recurse -Force
}
Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force

# Copy required DLLs
$RequiredDlls = @(
    "LibreHardwareMonitorLib.dll",
    "HidSharp.dll"
)

foreach ($dll in $RequiredDlls) {
    $source = Get-ChildItem -Path $TempExtract -Recurse -Filter $dll | Select-Object -First 1
    if ($source) {
        Copy-Item $source.FullName -Destination (Join-Path $LibDir $dll) -Force
        Write-Host "[+] Copied $dll" -ForegroundColor Green
    } else {
        Write-Host "[!] $dll not found in archive" -ForegroundColor Red
    }
}

# Cleanup
Remove-Item $TempZip -Force -ErrorAction SilentlyContinue
Remove-Item $TempExtract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[+] Done! DLLs installed to: $LibDir" -ForegroundColor Green
Write-Host "[i] Restart HumWatch to pick up LHM sensors." -ForegroundColor Cyan
