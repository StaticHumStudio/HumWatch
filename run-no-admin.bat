@echo off
:: ============================================================
::  HumWatch — Run without admin (psutil-only, no LHM sensors)
::  Temps, voltages, GPU, and fan data will be unavailable.
::  Ctrl+C to stop.
:: ============================================================

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

if exist "%ROOT%\venv\Scripts\activate.bat" (
    call "%ROOT%\venv\Scripts\activate.bat"
) else (
    echo [WARN] No venv found. Run setup.bat first, or using system Python.
)

title HumWatch - http://localhost:9100 (no admin)
echo.
echo  HumWatch starting on http://localhost:9100
echo  Running without admin - some sensors unavailable.
echo  Press Ctrl+C to stop.
echo.

cd /d "%ROOT%"
python -m agent.main
pause
