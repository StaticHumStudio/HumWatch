#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads LibreHardwareMonitor DLLs required by HumWatch.

.DESCRIPTION
    Fetches LibreHardwareMonitorLib.dll and HidSharp.dll from the official
    LibreHardwareMonitor GitHub releases and places them in the lib/ directory.

.NOTES
    Run once after cloning the repo:
        powershell -ExecutionPolicy Bypass -File scripts\download-lhm.ps1
#>

$ErrorActionPreference = "Stop"

$LHM_VERSION = "0.9.4"
$RELEASE_URL = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v${LHM_VERSION}/LibreHardwareMonitor-net472.zip"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LibDir = Join-Path $ProjectRoot "lib"
$TempZip = Join-Path $env:TEMP "lhm-${LHM_VERSION}.zip"
$TempExtract = Join-Path $env:TEMP "lhm-extract"

Write-Host "HumWatch — LibreHardwareMonitor Downloader" -ForegroundColor Yellow
Write-Host "==========================================="
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

# Download release zip
Write-Host "[*] Downloading LHM v${LHM_VERSION}..." -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $RELEASE_URL -OutFile $TempZip -UseBasicParsing
    Write-Host "[+] Download complete" -ForegroundColor Green
} catch {
    Write-Host "[!] Download failed: $_" -ForegroundColor Red
    Write-Host "    You can manually download from:" -ForegroundColor Yellow
    Write-Host "    $RELEASE_URL" -ForegroundColor Cyan
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
