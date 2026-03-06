@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  HumWatch — One-Click Setup
::  Run this once on a new machine. No admin required for setup.
::  (Admin only needed at runtime for hardware sensor access.)
:: ============================================================

title HumWatch Setup
color 0E
echo.
echo   =============================================
echo    HumWatch Setup
echo    What hums beneath the shell.
echo   =============================================
echo.

:: Determine project root (where this .bat lives)
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

:: ----- 1. Find Python -----
echo [1/6] Checking for Python...
where python3 >nul 2>&1
if %errorlevel%==0 (
    set "PY=python3"
    goto :found_python
)
where python >nul 2>&1
if %errorlevel%==0 (
    set "PY=python"
    goto :found_python
)
where py >nul 2>&1
if %errorlevel%==0 (
    set "PY=py -3"
    goto :found_python
)

echo.
echo   [ERROR] Python not found!
echo   Install Python 3.10+ from https://python.org
echo   Make sure "Add to PATH" is checked during install.
echo.
pause
exit /b 1

:found_python
for /f "tokens=*" %%i in ('%PY% --version 2^>^&1') do set "PY_VER=%%i"
echo   Found: %PY_VER%

:: ----- 2. Create virtual environment -----
echo.
echo [2/6] Setting up virtual environment...
if exist "%ROOT%\venv\Scripts\activate.bat" (
    echo   venv already exists, skipping creation.
) else (
    %PY% -m venv "%ROOT%\venv"
    if %errorlevel% neq 0 (
        echo   [ERROR] Failed to create venv. Make sure python3-venv is installed.
        pause
        exit /b 1
    )
    echo   Created venv/
)

:: Activate venv
call "%ROOT%\venv\Scripts\activate.bat"

:: ----- 3. Install dependencies -----
echo.
echo [3/6] Installing Python dependencies...
pip install --upgrade pip >nul 2>&1
pip install -r "%ROOT%\requirements.txt"
if %errorlevel% neq 0 (
    echo.
    echo   [WARN] Some packages may have failed.
    echo   pythonnet might not support your Python version.
    echo   HumWatch will still work without it (psutil-only mode).
    echo.
)

:: ----- 4. Download LibreHardwareMonitor DLLs -----
echo.
echo [4/6] Downloading LibreHardwareMonitor...
if exist "%ROOT%\lib\LibreHardwareMonitorLib.dll" (
    echo   LHM DLLs already present, skipping.
) else (
    powershell -ExecutionPolicy Bypass -Command ^
        "$ProgressPreference='SilentlyContinue'; " ^
        "$v='0.9.6'; " ^
        "$url='https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v' + $v + '/LibreHardwareMonitor.zip'; " ^
        "$zip=Join-Path $env:TEMP 'lhm.zip'; " ^
        "$ext=Join-Path $env:TEMP 'lhm-ext'; " ^
        "$lib='%ROOT%\lib'; " ^
        "New-Item -ItemType Directory -Path $lib -Force | Out-Null; " ^
        "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; " ^
        "$ok=$false; " ^
        "Write-Host '  Downloading LHM v0.9.6 (attempt 1: Invoke-WebRequest)...'; " ^
        "try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 60; $ok=$true } catch { Write-Host \"  Attempt 1 failed: $_\" }; " ^
        "if (-not $ok) { " ^
        "  Write-Host '  Downloading LHM v0.9.6 (attempt 2: WebClient)...'; " ^
        "  try { (New-Object System.Net.WebClient).DownloadFile($url, $zip); $ok=$true } catch { Write-Host \"  Attempt 2 failed: $_\" } " ^
        "}; " ^
        "if (-not $ok) { " ^
        "  Write-Host '  Downloading LHM v0.9.6 (attempt 3: curl)...'; " ^
        "  try { curl.exe -sL -o $zip $url --connect-timeout 30; if (Test-Path $zip) { $ok=$true } } catch { Write-Host \"  Attempt 3 failed: $_\" } " ^
        "}; " ^
        "if ($ok -and (Test-Path $zip)) { " ^
        "  $zipSize=(Get-Item $zip).Length; " ^
        "  if ($zipSize -lt 100000) { Write-Host '  [WARN] Downloaded file too small — possibly corrupt or blocked.'; $ok=$false; Remove-Item $zip -Force -EA SilentlyContinue } " ^
        "}; " ^
        "if ($ok) { " ^
        "  Write-Host '  Extracting...'; " ^
        "  if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }; " ^
        "  Expand-Archive -Path $zip -DestinationPath $ext -Force; " ^
        "  Get-ChildItem -Path $ext -Recurse -Filter 'LibreHardwareMonitorLib.dll' | Select-Object -First 1 | ForEach-Object { Copy-Item $_.FullName (Join-Path $lib 'LibreHardwareMonitorLib.dll') -Force }; " ^
        "  Get-ChildItem -Path $ext -Recurse -Filter 'HidSharp.dll' | Select-Object -First 1 | ForEach-Object { Copy-Item $_.FullName (Join-Path $lib 'HidSharp.dll') -Force }; " ^
        "  Remove-Item $zip -Force -EA SilentlyContinue; " ^
        "  Remove-Item $ext -Recurse -Force -EA SilentlyContinue " ^
        "} else { " ^
        "  Write-Host ''; Write-Host '  [WARN] All download attempts failed.' " ^
        "}; " ^
        "if (Test-Path (Join-Path $lib 'LibreHardwareMonitorLib.dll')) { " ^
        "  $dllSize=(Get-Item (Join-Path $lib 'LibreHardwareMonitorLib.dll')).Length / 1KB; " ^
        "  if ($dllSize -gt 100) { Write-Host \"  Done. LibreHardwareMonitorLib.dll ($([int]$dllSize) KB)\" } " ^
        "  else { Write-Host '  [WARN] DLL is suspiciously small — may be corrupt.' } " ^
        "} else { " ^
        "  Write-Host ''; " ^
        "  Write-Host '  ============================================'; " ^
        "  Write-Host '  LibreHardwareMonitor download FAILED.'; " ^
        "  Write-Host '  Without LHM you will only get basic metrics'; " ^
        "  Write-Host '  (CPU load, RAM, disk, network).'; " ^
        "  Write-Host '  No temps, GPU, fans, or voltages.'; " ^
        "  Write-Host ''; " ^
        "  Write-Host '  To fix manually:'; " ^
        "  Write-Host '    1. Download from: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases'; " ^
        "  Write-Host '    2. Extract LibreHardwareMonitorLib.dll and HidSharp.dll'; " ^
        "  Write-Host '    3. Place them in: %ROOT%\lib\'; " ^
        "  Write-Host '  ============================================'; " ^
        "  Write-Host '' " ^
        "}"
)

:: ----- 5. Verify installation -----
echo.
echo [5/6] Verifying installation...
echo.
python -m agent.verify
set "VERIFY_EXIT=%errorlevel%"
echo.

if %VERIFY_EXIT% equ 2 (
    color 0C
    echo   [!] Verification found ERRORS — see above.
    echo   Fix the issues before running HumWatch.
) else if %VERIFY_EXIT% equ 1 (
    color 0E
    echo   [i] Verification passed with warnings.
    echo   HumWatch will run, but some features may be limited.
) else (
    color 0A
    echo   [+] All checks passed.
)
echo.

:: ----- 6. Background service -----
echo.
echo   =============================================
echo   [6/6] Windows Background Service
echo   =============================================
echo.
echo   HumWatch can run as a Windows service that:
echo     - Starts automatically on every reboot
echo     - Runs silently in the background (no window)
echo     - Auto-restarts if it crashes
echo.
set /p INSTALL_SVC="   Install as a background service? (Y/n): "
if /i "%INSTALL_SVC%"=="n" goto :skip_service
if /i "%INSTALL_SVC%"=="no" goto :skip_service

:: Need admin for service install — auto-elevate
echo.
echo   [*] Installing background service (needs admin)...
echo   A UAC prompt may appear — click Yes to allow.
echo.
powershell -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-ExecutionPolicy Bypass -File \"%ROOT%\scripts\install-service.ps1\"'"
if %errorlevel% neq 0 (
    echo.
    echo   [WARN] Service install may have failed.
    echo   You can retry manually as Admin:
    echo     powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1
    echo.
)
goto :done

:skip_service
echo.
echo   Skipped service install. To run manually:
echo.
echo     run.bat              (as Administrator for full sensors)
echo     run-no-admin.bat     (without admin, psutil-only)
echo.
echo   To install as a service later:
echo     powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1
echo.

:done
echo.
echo   =============================================
echo    Setup Complete!
echo    Dashboard: http://localhost:9100
echo   =============================================
echo.
pause
