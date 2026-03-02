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
echo [1/4] Checking for Python...
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
echo [2/4] Setting up virtual environment...
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
echo [3/4] Installing Python dependencies...
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
echo [4/4] Downloading LibreHardwareMonitor...
if exist "%ROOT%\lib\LibreHardwareMonitorLib.dll" (
    echo   LHM DLLs already present, skipping.
) else (
    powershell -ExecutionPolicy Bypass -Command ^
        "$ProgressPreference='SilentlyContinue'; " ^
        "$v='0.9.4'; " ^
        "$url=\"https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v$v/LibreHardwareMonitor-net472.zip\"; " ^
        "$zip=\"$env:TEMP\lhm.zip\"; " ^
        "$ext=\"$env:TEMP\lhm-ext\"; " ^
        "$lib='%ROOT%\lib'; " ^
        "New-Item -ItemType Directory -Path $lib -Force | Out-Null; " ^
        "Write-Host '  Downloading LHM v0.9.4...'; " ^
        "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; " ^
        "try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing } catch { Write-Host '  [WARN] Download failed. LHM sensors won''t be available.'; exit 0 }; " ^
        "Expand-Archive -Path $zip -DestinationPath $ext -Force; " ^
        "Get-ChildItem -Path $ext -Recurse -Filter 'LibreHardwareMonitorLib.dll' | Select-Object -First 1 | ForEach-Object { Copy-Item $_.FullName \"$lib\LibreHardwareMonitorLib.dll\" -Force }; " ^
        "Get-ChildItem -Path $ext -Recurse -Filter 'HidSharp.dll' | Select-Object -First 1 | ForEach-Object { Copy-Item $_.FullName \"$lib\HidSharp.dll\" -Force }; " ^
        "Remove-Item $zip -Force -EA SilentlyContinue; " ^
        "Remove-Item $ext -Recurse -Force -EA SilentlyContinue; " ^
        "Write-Host '  Done.'"
)

:: ----- Done -----
echo.
color 0A
echo   =============================================
echo    Setup complete!
echo   =============================================
echo.
echo   To run HumWatch:
echo.
echo     run.bat              (as Administrator for full sensors)
echo     run-no-admin.bat     (without admin, psutil-only)
echo.
echo   Then open: http://localhost:9100
echo.
echo   To install as a Windows service (auto-start on boot):
echo     Run as Admin: scripts\install-service.ps1
echo.
pause
