@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  HumWatch — Update
::  Downloads the latest release, updates code and dependencies,
::  and restarts the background service. No git required.
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

:: ----- 2. Download latest release -----
echo.
echo [2/4] Checking for updates...
powershell -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; " ^
    "$ProgressPreference='SilentlyContinue'; " ^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; " ^
    "" ^
    "# Try gh CLI first (works with private repos)" ^
    "$useGh = $false; " ^
    "$gh = Get-Command gh -ErrorAction SilentlyContinue; " ^
    "if ($gh) { " ^
    "    try { " ^
    "        $rel = gh release view --repo StaticHumStudio/HumWatch --json tagName,assets 2>$null | ConvertFrom-Json; " ^
    "        if ($rel) { $useGh = $true } " ^
    "    } catch {} " ^
    "} " ^
    "" ^
    "if ($useGh) { " ^
    "    $tag = $rel.tagName; " ^
    "    $ver = $tag -replace '^v',''; " ^
    "    $currentVer = '%OLD_VER%'; " ^
    "    if ($ver -eq $currentVer) { " ^
    "        Write-Host '  Already on latest version (v' -NoNewline; Write-Host $ver -NoNewline; Write-Host ').'; " ^
    "        [System.IO.File]::WriteAllText('%ROOT%\_update_status.txt', 'CURRENT'); " ^
    "        exit 0; " ^
    "    } " ^
    "    Write-Host '  New version available: ' -NoNewline; Write-Host $tag -ForegroundColor Green; " ^
    "    $zipAsset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1; " ^
    "    $zipDest = Join-Path $env:TEMP 'humwatch-update.zip'; " ^
    "    if ($zipAsset) { " ^
    "        Write-Host '  Downloading ' $zipAsset.name '...'; " ^
    "        gh release download $tag --repo StaticHumStudio/HumWatch --pattern '*.zip' --output $zipDest --clobber 2>$null; " ^
    "    } else { " ^
    "        Write-Host '  Downloading source archive...'; " ^
    "        gh release download $tag --repo StaticHumStudio/HumWatch --archive zip --output $zipDest --clobber 2>$null; " ^
    "    } " ^
    "} else { " ^
    "    # Fall back to public GitHub API (no auth needed for public repos)" ^
    "    try { " ^
    "        $api = 'https://api.github.com/repos/StaticHumStudio/HumWatch/releases/latest'; " ^
    "        $rel = Invoke-RestMethod -Uri $api -UseBasicParsing; " ^
    "        $tag = $rel.tag_name; " ^
    "        $ver = $tag -replace '^v',''; " ^
    "        $currentVer = '%OLD_VER%'; " ^
    "        if ($ver -eq $currentVer) { " ^
    "            Write-Host '  Already on latest version (v' -NoNewline; Write-Host $ver -NoNewline; Write-Host ').'; " ^
    "            [System.IO.File]::WriteAllText('%ROOT%\_update_status.txt', 'CURRENT'); " ^
    "            exit 0; " ^
    "        } " ^
    "        Write-Host '  New version available: ' -NoNewline; Write-Host $tag -ForegroundColor Green; " ^
    "        $zipAsset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1; " ^
    "        $zipDest = Join-Path $env:TEMP 'humwatch-update.zip'; " ^
    "        if ($zipAsset) { " ^
    "            Write-Host '  Downloading ' $zipAsset.name '...'; " ^
    "            Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipDest -UseBasicParsing; " ^
    "        } else { " ^
    "            Write-Host '  Downloading source archive...'; " ^
    "            Invoke-WebRequest -Uri $rel.zipball_url -OutFile $zipDest -UseBasicParsing; " ^
    "        } " ^
    "    } catch { " ^
    "        Write-Host '  [ERROR] Could not reach GitHub. Check your network.' -ForegroundColor Red; " ^
    "        Write-Host '  If the repo is private, install GitHub CLI: https://cli.github.com/' -ForegroundColor Cyan; " ^
    "        [System.IO.File]::WriteAllText('%ROOT%\_update_status.txt', 'FAILED'); " ^
    "        exit 1; " ^
    "    } " ^
    "} " ^
    "" ^
    "# Extract over existing install (preserves venv, db, config, tools, lib, logs)" ^
    "$extractDir = Join-Path $env:TEMP 'humwatch-update-ext'; " ^
    "if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force } " ^
    "Expand-Archive -Path $zipDest -DestinationPath $extractDir -Force; " ^
    "" ^
    "# Find the root inside the zip (might be HumWatch/ or HumWatch-vX.Y.Z/ or repo-hash/)" ^
    "$innerDirs = Get-ChildItem $extractDir -Directory; " ^
    "if ($innerDirs.Count -eq 1) { $srcRoot = $innerDirs[0].FullName } else { $srcRoot = $extractDir } " ^
    "" ^
    "# Copy code files over (skip user data dirs)" ^
    "$preserve = @('venv','lib','tools','logs','dist','.git','humwatch.db','humwatch.db-shm','humwatch.db-wal','humwatch.log'); " ^
    "$codeDirs = @('agent','static','scripts'); " ^
    "foreach ($d in $codeDirs) { " ^
    "    $s = Join-Path $srcRoot $d; " ^
    "    $t = Join-Path '%ROOT%' $d; " ^
    "    if (Test-Path $s) { " ^
    "        if (Test-Path $t) { Remove-Item $t -Recurse -Force } " ^
    "        Copy-Item $s $t -Recurse -Force; " ^
    "    } " ^
    "} " ^
    "# Copy root files" ^
    "$rootFiles = @('config.json','requirements.txt','setup.bat','run.bat','run-no-admin.bat','update.bat','README.md','LICENSE','THEMING.md','.gitignore'); " ^
    "foreach ($f in $rootFiles) { " ^
    "    $s = Join-Path $srcRoot $f; " ^
    "    if (Test-Path $s) { Copy-Item $s (Join-Path '%ROOT%' $f) -Force } " ^
    "} " ^
    "" ^
    "# Cleanup" ^
    "Remove-Item $zipDest -Force -ErrorAction SilentlyContinue; " ^
    "Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue; " ^
    "[System.IO.File]::WriteAllText('%ROOT%\_update_status.txt', 'UPDATED'); " ^
    "Write-Host '  Files updated.'"

:: Check the result
if exist "%ROOT%\_update_status.txt" (
    set /p UPDATE_STATUS=<"%ROOT%\_update_status.txt"
    del "%ROOT%\_update_status.txt" >nul 2>&1
) else (
    set "UPDATE_STATUS=FAILED"
)

if "%UPDATE_STATUS%"=="CURRENT" (
    echo   Already up to date.
    goto :done
)
if "%UPDATE_STATUS%"=="FAILED" (
    echo   [ERROR] Update failed.
    pause
    exit /b 1
)

:: Get new version
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
    "%NSSM%" status HumWatch >nul 2>&1
    if !errorlevel!==0 (
        echo   Restarting HumWatch service...
        powershell -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-Command \"& { nssm restart HumWatch 2>&1 | Out-Null; Write-Host Done }\"'" >nul 2>&1
        if !errorlevel!==0 (
            echo   Service restarted.
        ) else (
            echo   [WARN] Could not restart. Run as Admin: nssm restart HumWatch
        )
    ) else (
        echo   No HumWatch service found. Start manually with run.bat
    )
) else (
    echo   Service manager not found. Start manually with run.bat
)

:done
:: ----- Done -----
echo.
color 0A
if defined NEW_VER (
    echo   =============================================
    echo    Update complete!  v%OLD_VER% -^> v%NEW_VER%
    echo   =============================================
) else (
    echo   =============================================
    echo    HumWatch is up to date.  v%OLD_VER%
    echo   =============================================
)
echo.
echo   Dashboard: http://localhost:9100
echo.
pause
