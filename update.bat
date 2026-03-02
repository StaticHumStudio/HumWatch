@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  HumWatch — Update
::  Pulls the latest code, updates dependencies, and restarts
::  the background service. Safe to re-run anytime.
:: ============================================================

title HumWatch Update
color 0E
echo.
echo   =============================================
echo    HumWatch Update
echo   =============================================
echo.

:: Determine project root (where this .bat lives)
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

:: ----- 1. Show current version -----
echo [1/4] Checking current version...
if exist "%ROOT%\venv\Scripts\python.exe" (
    set "PY=%ROOT%\venv\Scripts\python.exe"
) else (
    where python3 >nul 2>&1 && set "PY=python3" || (
        where python >nul 2>&1 && set "PY=python" || (
            where py >nul 2>&1 && set "PY=py -3" || (
                echo   [ERROR] Python not found. Run setup.bat first.
                pause
                exit /b 1
            )
        )
    )
)
for /f "tokens=*" %%i in ('%PY% -c "from agent import __version__; print(__version__)" 2^>^&1') do set "OLD_VER=%%i"
echo   Current version: v%OLD_VER%

:: ----- 2. Pull latest code -----
echo.
echo [2/4] Pulling latest code from GitHub...
where git >nul 2>&1
if %errorlevel% neq 0 (
    :: Try common install paths
    if exist "C:\Program Files\Git\bin\git.exe" (
        set "GIT=C:\Program Files\Git\bin\git.exe"
    ) else (
        echo   [ERROR] Git not found. Install from https://git-scm.com
        pause
        exit /b 1
    )
) else (
    set "GIT=git"
)
"%GIT%" -C "%ROOT%" pull origin main
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] Git pull failed. Check your network and try again.
    pause
    exit /b 1
)

:: Show new version
for /f "tokens=*" %%i in ('%PY% -c "from agent import __version__; print(__version__)" 2^>^&1') do set "NEW_VER=%%i"
echo   Updated: v%OLD_VER% -^> v%NEW_VER%

:: ----- 3. Update Python dependencies -----
echo.
echo [3/4] Updating dependencies...
if exist "%ROOT%\venv\Scripts\activate.bat" (
    call "%ROOT%\venv\Scripts\activate.bat"
)
pip install --upgrade pip >nul 2>&1
pip install -r "%ROOT%\requirements.txt" --quiet
if %errorlevel% neq 0 (
    echo   [WARN] Some packages may have failed.
)
echo   Dependencies updated.

:: ----- 4. Restart service (if installed) -----
echo.
echo [4/4] Restarting service...

:: Find nssm
set "NSSM="
if exist "%ROOT%\tools\nssm.exe" (
    set "NSSM=%ROOT%\tools\nssm.exe"
) else (
    where nssm >nul 2>&1 && set "NSSM=nssm"
)

if defined NSSM (
    :: Check if service is installed
    "%NSSM%" status HumWatch >nul 2>&1
    if !errorlevel!==0 (
        echo   Restarting HumWatch service...
        :: Need admin to restart service — auto-elevate
        powershell -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-Command \"& { nssm restart HumWatch 2>&1 | Out-Null; Write-Host HumWatch restarted }\"'" >nul 2>&1
        if !errorlevel!==0 (
            echo   Service restarted.
        ) else (
            echo   [WARN] Could not restart service. Restart manually:
            echo     nssm restart HumWatch
        )
    ) else (
        echo   No HumWatch service installed. Start manually with run.bat
    )
) else (
    echo   NSSM not found. If running as a service, restart manually.
    echo   Otherwise, start with run.bat
)

:: ----- Done -----
echo.
color 0A
echo   =============================================
echo    Update complete!  v%OLD_VER% -^> v%NEW_VER%
echo   =============================================
echo.
echo   Dashboard: http://localhost:9100
echo.
pause
