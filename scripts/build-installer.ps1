<#
.SYNOPSIS
    Builds the HumWatch Windows installer (.exe) using Inno Setup.

.DESCRIPTION
    Full build pipeline:
      1. Detect version from agent/__init__.py
      2. Create staging directory (dist/stage/)
      3. Copy HumWatch source files
      4. Download Python embeddable package (self-contained, no Python required on target)
      5. Bootstrap pip in the embedded Python
      6. pip install -r requirements.txt into the embedded Python
      7. Ensure NSSM is present (tools/nssm.exe)
      8. Ensure LibreHardwareMonitor DLLs are present (lib/)
      9. Find or download Inno Setup compiler (iscc.exe)
     10. Compile installer/HumWatch.iss -> dist/HumWatch-Setup-vX.Y.Z.exe
     11. Optionally create a GitHub release

.PARAMETER Version
    Override version string. Defaults to value in agent/__init__.py.

.PARAMETER PythonVersion
    Python embeddable version to bundle. Default: "3.12.9"

.PARAMETER SkipPythonDownload
    Skip downloading Python if dist/stage/python/ already exists.

.PARAMETER SkipLhmDownload
    Skip downloading LHM DLLs if lib/ already has them.

.PARAMETER CreateGitHubRelease
    After building, create or update a GitHub release with the installer attached.

.PARAMETER IsccPath
    Path to iscc.exe. If omitted, auto-detected or downloaded.

.NOTES
    Run from any directory:
        powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1

    For GitHub release:
        powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1 -CreateGitHubRelease

    Quick rebuild (skip Python re-download):
        powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1 -SkipPythonDownload
#>

param(
    [string]$Version            = "",
    [string]$PythonVersion      = "3.12.9",
    [switch]$SkipPythonDownload,
    [switch]$SkipLhmDownload,
    [switch]$CreateGitHubRelease,
    [string]$IsccPath           = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$DistDir     = Join-Path $ProjectRoot "dist"
$StageDir    = Join-Path $DistDir "stage"

# ---- Helpers ---------------------------------------------------------------

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "  $msg" -ForegroundColor Yellow
}

function Write-Ok([string]$msg)   { Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-Info([string]$msg) { Write-Host "  [i] $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "  [!] $msg" -ForegroundColor DarkYellow }
function Write-Fail([string]$msg) { Write-Host "  [X] $msg" -ForegroundColor Red; exit 1 }

function Get-FileFromUrl([string]$url, [string]$dest, [string]$label) {
    Write-Info "Downloading $label..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 120
        $mb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Write-Ok "Downloaded $label ($mb MB)"
        return $true
    } catch { Write-Warn "Invoke-WebRequest failed: $_. Trying WebClient..." }
    try {
        (New-Object System.Net.WebClient).DownloadFile($url, $dest)
        Write-Ok "Downloaded $label"
        return $true
    } catch {
        Write-Warn "WebClient failed: $_"
        return $false
    }
}

# ---- Banner ----------------------------------------------------------------

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host "   HumWatch -- Installer Builder" -ForegroundColor Yellow
Write-Host "   A Static Hum Studio Production" -ForegroundColor DarkYellow
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host ""

# ---- Step 1: Detect version ------------------------------------------------

Write-Step "[1/9] Detecting version..."

if (-not $Version) {
    $initFile = Join-Path $ProjectRoot "agent\__init__.py"
    if (Test-Path $initFile) {
        $versionLine = (Get-Content $initFile) |
            Where-Object { $_ -like '*__version__*' } |
            Select-Object -First 1
        if ($versionLine) {
            $Version = ($versionLine -split '=')[1].Trim().Trim('"').Trim("'")
        }
    }
}
if (-not $Version) { Write-Fail "Cannot detect version. Use -Version x.y.z" }
Write-Ok "Version: $Version"

# ---- Step 2: Create staging directory -------------------------------------

Write-Step "[2/9] Setting up staging directory..."

if (Test-Path $StageDir) {
    Get-ChildItem $StageDir | Where-Object { $_.Name -ne "python" } | Remove-Item -Recurse -Force
    Write-Info "Cleaned stage/ (preserved python/ if present)"
} else {
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
}

New-Item -ItemType Directory -Path "$StageDir\tools" -Force | Out-Null
New-Item -ItemType Directory -Path "$StageDir\lib"   -Force | Out-Null
Write-Ok "Staging directory: $StageDir"

# ---- Step 3: Copy source files --------------------------------------------

Write-Step "[3/9] Copying HumWatch source files..."

function Copy-DirFiltered([string]$src, [string]$dst) {
    $excludeDirs  = @("__pycache__", ".git", "venv", "node_modules")
    $excludeExts  = @(".pyc", ".pyo", ".db", ".db-shm", ".db-wal")
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Get-ChildItem -Path $src -Recurse | ForEach-Object {
        if ($_.PSIsContainer) { return }
        # Skip excluded dirs
        $relPath = $_.FullName.Substring($src.Length).TrimStart('\')
        foreach ($xd in $excludeDirs) {
            if ($relPath -match "(?i)(^|\\)$([regex]::Escape($xd))(\\|$)") { return }
        }
        # Skip excluded extensions
        if ($excludeExts -contains $_.Extension.ToLower()) { return }
        $destFile = Join-Path $dst $relPath
        $destDir  = Split-Path $destFile
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item $_.FullName -Destination $destFile -Force
    }
}

$dirsToStage = @("agent", "static", "installer")
foreach ($d in $dirsToStage) {
    $src = Join-Path $ProjectRoot $d
    $dst = Join-Path $StageDir $d
    if (Test-Path $src) {
        Copy-DirFiltered $src $dst
        Write-Ok "Copied $d/"
    } else {
        Write-Warn "Not found, skipping: $d"
    }
}

$filesToStage = @("config.json", "README.md", "LICENSE", "THEMING.md")
foreach ($f in $filesToStage) {
    $src = Join-Path $ProjectRoot $f
    if (Test-Path $src) {
        Copy-Item $src -Destination $StageDir -Force
        Write-Ok "Copied $f"
    } else {
        Write-Warn "Not found, skipping: $f"
    }
}

# ---- Ensure icon exists (Inno Setup needs it) -----------------------------

$iconPath = Join-Path $StageDir "static\img\icon.ico"
if (-not (Test-Path $iconPath)) {
    Write-Warn "icon.ico not found at static/img/icon.ico -- using placeholder."
    New-Item -ItemType Directory -Path (Split-Path $iconPath) -Force | Out-Null
    # Minimal valid 1x1 .ico
    $minIcoBytes = [byte[]](
        0,0,1,0,1,0,1,1,0,0,1,0,32,0,40,0,0,0,22,0,0,0,40,0,0,0,1,0,0,0,2,0,
        0,0,1,0,32,0,0,0,0,0,16,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,255,255)
    [IO.File]::WriteAllBytes($iconPath, $minIcoBytes)
    Write-Info "Placeholder icon created."
}

# ---- Step 4: Python embeddable -------------------------------------------

Write-Step "[4/9] Setting up embedded Python $PythonVersion..."

$PyStageDirPath = Join-Path $StageDir "python"
$PyEmbedZip     = Join-Path $DistDir "python-$PythonVersion-embed-amd64.zip"
$PyMajorMinor   = ($PythonVersion -split '\.')[0..1] -join ""   # e.g. "312"

if ($SkipPythonDownload -and (Test-Path "$PyStageDirPath\python.exe")) {
    Write-Info "Skipping Python download (-SkipPythonDownload)."
} else {
    if (-not (Test-Path $PyEmbedZip)) {
        New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
        $PyUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
        $ok = Get-FileFromUrl $PyUrl $PyEmbedZip "Python $PythonVersion embeddable"
        if (-not $ok) { Write-Fail "Python download failed." }
    } else {
        Write-Info "Using cached Python embed: $PyEmbedZip"
    }

    Write-Info "Extracting Python embeddable..."
    if (Test-Path $PyStageDirPath) { Remove-Item $PyStageDirPath -Recurse -Force }
    Expand-Archive -Path $PyEmbedZip -DestinationPath $PyStageDirPath -Force
    Write-Ok "Extracted Python $PythonVersion"

    # Enable site-packages (required for pip) and add parent dir to sys.path.
    # Adding ".." ensures "python -m agent.main" finds the agent package even
    # when NSSM starts Python from the python\ subfolder instead of the
    # install root (C:\HumWatch).
    $pthFile = Join-Path $PyStageDirPath "python$PyMajorMinor._pth"
    if (Test-Path $pthFile) {
        $lines = [System.IO.File]::ReadAllLines($pthFile)
        $newLines = [System.Collections.Generic.List[string]]::new()
        $hasDotDot = $false
        foreach ($line in $lines) {
            # Uncomment "import site" if commented
            if ($line.Trim() -eq "#import site") {
                $newLines.Add("import site")
            } else {
                $newLines.Add($line)
            }
            # Insert ".." after "." if not already present
            if ($line.Trim() -eq "." -and -not $hasDotDot) {
                $hasDotDot = ($lines | Where-Object { $_.Trim() -eq ".." }).Count -gt 0
                if (-not $hasDotDot) {
                    $newLines.Add("..")
                    $hasDotDot = $true
                }
            }
        }
        [System.IO.File]::WriteAllLines($pthFile, $newLines.ToArray())
        Write-Ok "Enabled site-packages and parent-dir path in python$PyMajorMinor._pth"
    } else {
        Write-Warn "._pth file not found at: $pthFile"
    }

    # Bootstrap pip
    Write-Info "Bootstrapping pip..."
    $getPipPath = Join-Path $env:TEMP "get-pip.py"
    $ok = Get-FileFromUrl "https://bootstrap.pypa.io/get-pip.py" $getPipPath "get-pip.py"
    if (-not $ok) { Write-Fail "Could not download get-pip.py." }

    $pyExe = Join-Path $PyStageDirPath "python.exe"
    # Use SilentlyContinue to prevent 2>&1 stderr lines becoming terminating errors
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $pipOut = & $pyExe $getPipPath --no-warn-script-location 2>&1
    $pipExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($pipExit -ne 0) { Write-Fail "pip bootstrap failed (exit $pipExit). Output: $pipOut" }
    Write-Ok "pip installed"

    # Install requirements
    Write-Info "Installing Python dependencies (may take a minute)..."
    $reqFile = Join-Path $ProjectRoot "requirements.txt"
    $ErrorActionPreference = "SilentlyContinue"
    $installOut = & $pyExe -m pip install -r $reqFile --no-warn-script-location 2>&1
    $installExit = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    $installOut | Where-Object { $_ -match "Successfully installed" } | ForEach-Object { Write-Ok $_ }
    if ($installExit -ne 0) { Write-Fail "pip install failed (exit $installExit)." }
    Write-Ok "All Python dependencies installed"

    Remove-Item $getPipPath -Force -ErrorAction SilentlyContinue
}

# Always ensure the ._pth file has the parent-dir entry, even when
# -SkipPythonDownload was used (the patching above only runs on fresh extract).
$pthFile = Join-Path $PyStageDirPath "python$PyMajorMinor._pth"
if (Test-Path $pthFile) {
    $lines = [System.IO.File]::ReadAllLines($pthFile)
    $hasDotDot = ($lines | Where-Object { $_.Trim() -eq ".." }).Count -gt 0
    if (-not $hasDotDot) {
        $newLines = [System.Collections.Generic.List[string]]::new()
        $inserted = $false
        foreach ($line in $lines) {
            $newLines.Add($line)
            if (-not $inserted -and $line.Trim() -eq ".") {
                $newLines.Add("..")
                $inserted = $true
            }
        }
        if (-not $inserted) { $newLines.Add("..") }
        [System.IO.File]::WriteAllLines($pthFile, $newLines.ToArray())
        Write-Ok "Patched python$PyMajorMinor._pth: added parent-dir (..)"
    }
}

$pySize = [math]::Round(
    (Get-ChildItem $PyStageDirPath -Recurse | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Info "Embedded Python bundle: $pySize MB"

# ---- Step 5: NSSM --------------------------------------------------------

Write-Step "[5/9] Ensuring NSSM is present..."

$NssmSource = Join-Path $ProjectRoot "tools\nssm.exe"
$NssmStage  = Join-Path $StageDir "tools\nssm.exe"

if (Test-Path $NssmSource) {
    Copy-Item $NssmSource $NssmStage -Force
    Write-Ok "Copied nssm.exe from tools/"
} else {
    $nssmZip     = Join-Path $env:TEMP "nssm.zip"
    $nssmExtract = Join-Path $env:TEMP "nssm-extract"
    $ok = Get-FileFromUrl "https://nssm.cc/release/nssm-2.24.zip" $nssmZip "NSSM 2.24"
    if (-not $ok) { Write-Fail "NSSM download failed." }
    Expand-Archive -Path $nssmZip -DestinationPath $nssmExtract -Force
    $nssmBin = Get-ChildItem -Path $nssmExtract -Recurse -Filter "nssm.exe" |
        Where-Object { $_.DirectoryName -match "win64" } | Select-Object -First 1
    if (-not $nssmBin) {
        $nssmBin = Get-ChildItem -Path $nssmExtract -Recurse -Filter "nssm.exe" | Select-Object -First 1
    }
    New-Item -ItemType Directory -Path (Split-Path $NssmSource) -Force | Out-Null
    Copy-Item $nssmBin.FullName $NssmSource -Force
    Copy-Item $nssmBin.FullName $NssmStage  -Force
    Remove-Item $nssmZip, $nssmExtract -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "NSSM downloaded and staged"
}

# ---- Step 6: LibreHardwareMonitor DLLs ------------------------------------

Write-Step "[6/9] Ensuring LibreHardwareMonitor DLLs are present..."

$LhmLibDir   = Join-Path $ProjectRoot "lib"
$LhmStageDir = Join-Path $StageDir "lib"
$LhmDll      = Join-Path $LhmLibDir "LibreHardwareMonitorLib.dll"

if (Test-Path $LhmDll) {
    Copy-Item "$LhmLibDir\*" $LhmStageDir -Force
    Write-Ok "Copied LHM DLLs from lib/"
} else {
    $lhmVersion = "0.9.6"
    $lhmZip     = Join-Path $env:TEMP "lhm.zip"
    $lhmExtract = Join-Path $env:TEMP "lhm-extract"
    $lhmUrl     = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v$lhmVersion/LibreHardwareMonitor.zip"
    $ok = Get-FileFromUrl $lhmUrl $lhmZip "LibreHardwareMonitor $lhmVersion"
    if (-not $ok) { Write-Fail "LHM download failed." }
    Expand-Archive -Path $lhmZip -DestinationPath $lhmExtract -Force
    New-Item -ItemType Directory -Path $LhmLibDir -Force | Out-Null
    foreach ($dll in @("LibreHardwareMonitorLib.dll", "HidSharp.dll")) {
        $src = Get-ChildItem -Path $lhmExtract -Recurse -Filter $dll | Select-Object -First 1
        if ($src) {
            Copy-Item $src.FullName -Destination (Join-Path $LhmLibDir $dll)   -Force
            Copy-Item $src.FullName -Destination (Join-Path $LhmStageDir $dll) -Force
            Write-Ok "Downloaded and staged: $dll"
        } else {
            Write-Warn "$dll not found in LHM archive"
        }
    }
    Remove-Item $lhmZip, $lhmExtract -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- Step 7: Find Inno Setup ----------------------------------------------

Write-Step "[7/9] Locating Inno Setup compiler (iscc.exe)..."

function Find-Iscc {
    if ($IsccPath -and (Test-Path $IsccPath)) { return $IsccPath }
    $pf86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $pf64 = [Environment]::GetFolderPath("ProgramFiles")
    $candidates = @(
        "$pf86\Inno Setup 6\ISCC.exe",
        "$pf64\Inno Setup 6\ISCC.exe",
        "$pf86\Inno Setup 5\ISCC.exe",
        "$pf64\Inno Setup 5\ISCC.exe",
        "C:\InnoSetup\ISCC.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

$iscc = Find-Iscc

if (-not $iscc) {
    Write-Warn "Inno Setup not found. Downloading and installing silently..."
    $isSetupExe = Join-Path $env:TEMP "innosetup.exe"
    $ok = Get-FileFromUrl "https://jrsoftware.org/download.php/is.exe" $isSetupExe "Inno Setup 6"
    if (-not $ok) { Write-Fail "Could not download Inno Setup. Install from https://jrsoftware.org/isdl.php" }
    Start-Process -FilePath $isSetupExe -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
    Remove-Item $isSetupExe -Force -ErrorAction SilentlyContinue
    $iscc = Find-Iscc
    if (-not $iscc) { Write-Fail "Inno Setup installed but iscc.exe still not found. Please install manually." }
    Write-Ok "Inno Setup installed: $iscc"
} else {
    Write-Ok "Found iscc.exe: $iscc"
}

# ---- Step 8: Compile installer --------------------------------------------

Write-Step "[8/9] Compiling installer..."

$IssFile   = Join-Path $ProjectRoot "installer\HumWatch.iss"
if (-not (Test-Path $IssFile)) { Write-Fail "HumWatch.iss not found at: $IssFile" }

$OutputExe = Join-Path $DistDir "HumWatch-Setup-v$Version.exe"
if (Test-Path $OutputExe) { Remove-Item $OutputExe -Force }

Write-Info "Running iscc.exe..."
# Note: /D defines must come BEFORE the .iss file on the command line
# Use Start-Process to reliably capture exit code (2>&1 interferes with $LASTEXITCODE)
$isccLogFile = Join-Path $env:TEMP "humwatch-iscc-build.log"
$isccArgs    = @(
    "/DMyAppVersion=$Version",
    "/DStageDir=$StageDir",
    "/O$DistDir",
    $IssFile
)
$proc = Start-Process -FilePath $iscc `
    -ArgumentList $isccArgs `
    -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $isccLogFile `
    -RedirectStandardError  "$isccLogFile.err"
$isccExit = $proc.ExitCode

# Show relevant log lines
if (Test-Path $isccLogFile) {
    Get-Content $isccLogFile | ForEach-Object {
        if ($_ -match "^(Compiling|Linking|Output|Successful)") { Write-Info $_ }
        elseif ($_ -match "(?i)(error|warning|failed)")         { Write-Warn $_ }
    }
}

if ($isccExit -ne 0) {
    if (Test-Path "$isccLogFile.err") { Get-Content "$isccLogFile.err" | ForEach-Object { Write-Warn $_ } }
    Write-Fail "Inno Setup compilation failed (exit $isccExit)."
}
Remove-Item $isccLogFile, "$isccLogFile.err" -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $OutputExe)) { Write-Fail "Expected output not found: $OutputExe" }

$exeSizeMb = [math]::Round((Get-Item $OutputExe).Length / 1MB, 1)
Write-Ok "Installer built: HumWatch-Setup-v$Version.exe ($exeSizeMb MB)"

# ---- Step 9: Optional GitHub release --------------------------------------

if ($CreateGitHubRelease) {
    Write-Step "[9/9] Creating GitHub release..."

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-Warn "GitHub CLI (gh) not found. Install from: https://cli.github.com/"
        Write-Info "Installer is at: $OutputExe"
    } else {
        $tag = "v$Version"
        $releaseNotes = "## HumWatch v$Version`n`n" +
            "### Installation`n" +
            "1. Download **HumWatch-Setup-v$Version.exe**`n" +
            "2. Run it (SmartScreen warning -- click **More info -> Run anyway**)`n" +
            "3. Follow the installer. It handles everything automatically:`n" +
            "   - Installs a self-contained Python runtime (no Python required)`n" +
            "   - Installs LibreHardwareMonitor for full CPU/GPU sensor access`n" +
            "   - Registers a Windows service that starts automatically on every boot`n" +
            "4. Open **http://localhost:9100**`n`n" +
            "### Requirements`n" +
            "- Windows 10 version 1809 or later (64-bit)`n`n" +
            "---`n" +
            "*A Static Hum Studio Production -- What hums beneath the shell.*"

        $existingRelease = & gh release view $tag 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Release $tag already exists. Uploading asset..."
            & gh release upload $tag $OutputExe --clobber
        } else {
            & gh release create $tag $OutputExe --title "HumWatch $tag" --notes $releaseNotes
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Ok "GitHub release: $tag"
        } else {
            Write-Warn "GitHub release failed. Installer is at: $OutputExe"
        }
    }
} else {
    Write-Step "[9/9] Skipping GitHub release (use -CreateGitHubRelease to publish)"
}

# ---- Done -----------------------------------------------------------------

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "   Build complete!" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Installer : $OutputExe" -ForegroundColor Cyan
Write-Host "  Size      : $exeSizeMb MB" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To publish a GitHub release:" -ForegroundColor Yellow
Write-Host "    .\scripts\build-installer.ps1 -CreateGitHubRelease" -ForegroundColor White
Write-Host ""
Write-Host "  Quick rebuild (skip Python re-download):" -ForegroundColor Yellow
Write-Host "    .\scripts\build-installer.ps1 -SkipPythonDownload" -ForegroundColor White
Write-Host ""
