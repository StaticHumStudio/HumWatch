<#
.SYNOPSIS
    Builds a portable HumWatch release zip.

.DESCRIPTION
    Creates a clean zip archive containing all files needed to run HumWatch
    on a new machine. The end user extracts the zip, runs setup.bat, then run.bat.

.PARAMETER Version
    Version tag for the zip filename. Defaults to the version in agent/__init__.py.

.PARAMETER OutputDir
    Directory to place the zip. Defaults to dist/ in the project root.

.PARAMETER CreateGitHubRelease
    If specified, creates a GitHub release with the zip attached using gh CLI.

.NOTES
    Usage:
        powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1
        powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1 -Version "0.10.0"
        powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1 -CreateGitHubRelease
#>

param(
    [string]$Version = "",
    [string]$OutputDir = "",
    [switch]$CreateGitHubRelease
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host ""
Write-Host "HumWatch - Release Builder" -ForegroundColor Yellow
Write-Host "==========================" -ForegroundColor Yellow
Write-Host ""

# ── Step 1: Detect version ──────────────────────────────────────────────

if (-not $Version) {
    $InitFile = Join-Path $ProjectRoot "agent\__init__.py"
    if (Test-Path $InitFile) {
        $Content = Get-Content $InitFile -Raw
        if ($Content -match '__version__\s*=\s*"([^"]+)"') {
            $Version = $Matches[1]
        }
    }
    if (-not $Version) {
        Write-Host "[!] Could not detect version from agent/__init__.py." -ForegroundColor Red
        Write-Host "    Specify manually with: -Version `"0.10.0`"" -ForegroundColor Cyan
        exit 1
    }
}
Write-Host "[i] Version: $Version" -ForegroundColor Cyan

# ── Step 2: Set up output directory ─────────────────────────────────────

if (-not $OutputDir) {
    $OutputDir = Join-Path $ProjectRoot "dist"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$ZipName = "HumWatch-v${Version}.zip"
$ZipPath = Join-Path $OutputDir $ZipName
Write-Host "[i] Output: $ZipPath" -ForegroundColor Cyan
Write-Host ""

# ── Step 3: Create staging directory ────────────────────────────────────

$StagingDir = Join-Path $env:TEMP "humwatch-release-$Version"
if (Test-Path $StagingDir) {
    Remove-Item $StagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingDir | Out-Null
$StageRoot = Join-Path $StagingDir "HumWatch"
New-Item -ItemType Directory -Path $StageRoot | Out-Null

# ── Step 4: Copy files ──────────────────────────────────────────────────

# Directories to include
$IncludeDirs = @("agent", "static", "scripts")

foreach ($dir in $IncludeDirs) {
    $src = Join-Path $ProjectRoot $dir
    $dst = Join-Path $StageRoot $dir
    if (Test-Path $src) {
        # robocopy: /E recurse, /XD exclude dirs, /XF exclude files
        & robocopy $src $dst /E `
            /XD "__pycache__" ".git" "venv" "node_modules" `
            /XF "*.pyc" "*.pyo" "*.db" "*.db-shm" "*.db-wal" `
            /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        Write-Host "[+] Copied $dir/" -ForegroundColor Green
    }
}

# Root files to include
$IncludeFiles = @(
    "config.json",
    "requirements.txt",
    "setup.bat",
    "run.bat",
    "run-no-admin.bat",
    "README.md",
    "LICENSE",
    "THEMING.md",
    ".gitignore"
)

foreach ($file in $IncludeFiles) {
    $src = Join-Path $ProjectRoot $file
    if (Test-Path $src) {
        Copy-Item $src -Destination (Join-Path $StageRoot $file) -Force
        Write-Host "[+] Copied $file" -ForegroundColor Green
    } else {
        Write-Host "[~] Skipped $file (not found)" -ForegroundColor DarkYellow
    }
}

# ── Step 5: Remove anything that shouldn't ship ─────────────────────────

$RemoveIfPresent = @(
    "HumWatch-Spec.md",
    ".git",
    "venv",
    ".vscode",
    ".idea",
    "lib",
    "logs",
    "dist",
    "humwatch.db",
    "humwatch.log"
)

foreach ($item in $RemoveIfPresent) {
    $path = Join-Path $StageRoot $item
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force
        Write-Host "[*] Removed excluded: $item" -ForegroundColor Yellow
    }
}

# ── Step 6: Create zip archive ──────────────────────────────────────────

Write-Host ""
Write-Host "[*] Creating zip archive..." -ForegroundColor Yellow

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
Compress-Archive -Path $StageRoot -DestinationPath $ZipPath -CompressionLevel Optimal

$ZipSize = (Get-Item $ZipPath).Length / 1MB
Write-Host "[+] Created: $ZipName ($([math]::Round($ZipSize, 2)) MB)" -ForegroundColor Green

# ── Step 7: Cleanup staging ─────────────────────────────────────────────

Remove-Item $StagingDir -Recurse -Force
Write-Host "[+] Cleaned up staging directory" -ForegroundColor Green

# ── Step 8: Optional GitHub release ─────────────────────────────────────

if ($CreateGitHubRelease) {
    Write-Host ""
    Write-Host "[*] Creating GitHub release..." -ForegroundColor Yellow

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-Host "[!] GitHub CLI (gh) not found. Install from: https://cli.github.com/" -ForegroundColor Red
        Write-Host "    The zip has been created at: $ZipPath" -ForegroundColor Cyan
    } else {
        $Tag = "v$Version"

        # Check if tag already exists
        $existingRelease = & gh release view $Tag 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[!] Release $Tag already exists. Uploading asset to existing release..." -ForegroundColor Yellow
            & gh release upload $Tag $ZipPath --clobber
        } else {
            & gh release create $Tag $ZipPath `
                --title "HumWatch $Tag" `
                --notes "Portable release. Extract, run setup.bat, then run.bat. See README.md for details."
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] GitHub release ready: $Tag" -ForegroundColor Green
        } else {
            Write-Host "[!] GitHub release failed. Zip is at: $ZipPath" -ForegroundColor Red
        }
    }
}

# ── Done ────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""
Write-Host "  Zip: $ZipPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "  End-user setup:" -ForegroundColor Yellow
Write-Host "    1. Extract HumWatch-v${Version}.zip" -ForegroundColor White
Write-Host "    2. Double-click setup.bat  (one-time)" -ForegroundColor White
Write-Host "    3. Double-click run.bat" -ForegroundColor White
Write-Host "    4. Open http://localhost:9100" -ForegroundColor White
Write-Host ""
