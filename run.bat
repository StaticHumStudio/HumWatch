@echo off
:: ============================================================
::  HumWatch — Run (with admin elevation for full sensor access)
::  Ctrl+C to stop.
:: ============================================================

:: Check for admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
    exit /b
)

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

:: Use venv if it exists, otherwise system Python
if exist "%ROOT%\venv\Scripts\activate.bat" (
    call "%ROOT%\venv\Scripts\activate.bat"
) else (
    echo [WARN] No venv found. Run setup.bat first, or using system Python.
)

title HumWatch - http://localhost:9100
echo.
echo  HumWatch starting on http://localhost:9100
echo  Press Ctrl+C to stop.
echo.

cd /d "%ROOT%"
python -m agent.main
pause
