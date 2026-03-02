#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes the HumWatch Windows service.

.DESCRIPTION
    Stops the HumWatch service (if running) and removes it via NSSM.
    Does not delete logs, database, or configuration files.

.NOTES
    Run as Administrator:
        powershell -ExecutionPolicy Bypass -File scripts\uninstall-service.ps1
#>

$ErrorActionPreference = "Stop"

$ServiceName = "HumWatch"

Write-Host "HumWatch — Service Uninstaller" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow
Write-Host ""

# Find NSSM
$Nssm = Get-Command nssm -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $Nssm) {
    Write-Host "[!] NSSM not found on PATH." -ForegroundColor Red
    Write-Host "    Cannot uninstall service without NSSM." -ForegroundColor Yellow
    exit 1
}

# Check if service exists
$status = & $Nssm status $ServiceName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[i] Service '$ServiceName' is not installed." -ForegroundColor Cyan
    exit 0
}

Write-Host "[i] Current status: $status" -ForegroundColor Cyan
$response = Read-Host "    Remove the HumWatch service? (y/N)"
if ($response -ne 'y' -and $response -ne 'Y') {
    Write-Host "[i] Cancelled." -ForegroundColor Cyan
    exit 0
}

# Stop if running
if ($status -eq "SERVICE_RUNNING") {
    Write-Host "[*] Stopping service..." -ForegroundColor Yellow
    & $Nssm stop $ServiceName
    Start-Sleep -Seconds 2
}

# Remove
Write-Host "[*] Removing service..." -ForegroundColor Yellow
& $Nssm remove $ServiceName confirm

Write-Host ""
Write-Host "[+] HumWatch service removed." -ForegroundColor Green
Write-Host "[i] Data files (database, logs, config) were not deleted." -ForegroundColor Cyan
