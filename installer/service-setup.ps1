<#
.SYNOPSIS
    Installs or uninstalls the HumWatch Windows service.
    Bundled inside the installer -- called by Inno Setup [Run]/[UninstallRun].

.PARAMETER Action
    "install" or "uninstall"

.PARAMETER AppDir
    The HumWatch installation directory (e.g. C:\HumWatch)
#>

param(
    [Parameter(Mandatory)][ValidateSet("install","uninstall")][string]$Action,
    [Parameter(Mandatory)][string]$AppDir
)

$ErrorActionPreference = "Stop"

$ServiceName = "HumWatch"
$NssmPath    = Join-Path $AppDir "tools\nssm.exe"
$PythonPath  = Join-Path $AppDir "python\python.exe"
$LogDir      = Join-Path $AppDir "logs"
$ParamKey    = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"

# ---------------------------------------------------------------------------
#  Logging helper
# ---------------------------------------------------------------------------

$LogFile = Join-Path $LogDir "service-setup.log"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
#  Helper: run NSSM and return exit code
#  Uses direct invocation (&) to inherit the elevated token from the
#  Inno Setup installer process.
# ---------------------------------------------------------------------------

function Invoke-Nssm {
    param([string[]]$Arguments)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    & $NssmPath @Arguments 2>&1 | Out-Null
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    return $rc
}

# ---------------------------------------------------------------------------
#  Helper: set an NSSM parameter with verification and registry fallback
# ---------------------------------------------------------------------------

function Set-NssmParam {
    param(
        [string]$Name,
        [string[]]$Values
    )

    # Try NSSM set first
    $args = @("set", $ServiceName, $Name) + $Values
    $rc = Invoke-Nssm $args
    if ($rc -eq 0) {
        Write-Log "  OK: $Name = $($Values -join ' ') (nssm)"
        return $true
    }

    Write-Log "  WARN: nssm set $Name failed (exit $rc), falling back to registry"

    # Registry fallback — only works for single-value string parameters
    if ($Values.Count -eq 1) {
        try {
            if (-not (Test-Path $ParamKey)) {
                New-Item -Path $ParamKey -Force | Out-Null
            }
            Set-ItemProperty -Path $ParamKey -Name $Name -Value $Values[0] -ErrorAction Stop
            Write-Log "  OK: $Name = $($Values[0]) (registry)"
            return $true
        } catch {
            Write-Log "  FAIL: registry write for $Name also failed: $_"
            return $false
        }
    }

    Write-Log "  FAIL: cannot registry-fallback for multi-value param $Name"
    return $false
}

# ---------------------------------------------------------------------------
#  Patch python312._pth — ensure the agent package is importable
# ---------------------------------------------------------------------------

function Patch-PythonPath {
    # The embedded Python's ._pth file controls sys.path.  NSSM sets the
    # working directory to wherever python.exe lives (python\ subfolder),
    # so "." resolves to the python\ dir.  Adding ".." puts the install
    # root (C:\HumWatch) on sys.path, making "python -m agent.main" work.

    $pthFile = Join-Path $AppDir "python\python312._pth"
    if (-not (Test-Path $pthFile)) {
        Write-Log "WARNING: python312._pth not found at $pthFile"
        return $false
    }

    $lines = [System.IO.File]::ReadAllLines($pthFile)
    $hasDotDot = $lines | Where-Object { $_.Trim() -eq ".." }

    if ($hasDotDot) {
        Write-Log "python312._pth already has parent-dir entry (..)"
        return $true
    }

    # Insert ".." right after the "." line.  If "." isn't found, append.
    $newLines = [System.Collections.Generic.List[string]]::new()
    $inserted = $false
    foreach ($line in $lines) {
        $newLines.Add($line)
        if (-not $inserted -and $line.Trim() -eq ".") {
            $newLines.Add("..")
            $inserted = $true
        }
    }
    if (-not $inserted) {
        $newLines.Add("..")
    }

    [System.IO.File]::WriteAllLines($pthFile, $newLines.ToArray())

    # Verify the write succeeded
    $verify = [System.IO.File]::ReadAllLines($pthFile)
    $ok = ($verify | Where-Object { $_.Trim() -eq ".." }).Count -gt 0
    if ($ok) {
        Write-Log "Patched python312._pth: added parent-dir (..) to sys.path"
    } else {
        Write-Log "ERROR: wrote python312._pth but verification failed"
    }
    return $ok
}

# ---------------------------------------------------------------------------
#  Remove existing service
# ---------------------------------------------------------------------------

function Remove-HumWatchService {
    $svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Log "Stopping existing service..."
        try { Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Seconds 2
        Write-Log "Removing existing service..."
        Invoke-Nssm @("remove", $ServiceName, "confirm") | Out-Null
        Start-Sleep -Seconds 2
        # Belt-and-suspenders: sc.exe delete if NSSM remove didn't clean up
        $still = Get-Service $ServiceName -ErrorAction SilentlyContinue
        if ($still) {
            sc.exe delete $ServiceName | Out-Null
            Start-Sleep -Seconds 2
        }
        Write-Log "Service removed."
    } else {
        Write-Log "No existing service found."
    }
}

# ---------------------------------------------------------------------------
#  UNINSTALL
# ---------------------------------------------------------------------------

if ($Action -eq "uninstall") {
    Write-Log "=== Uninstall started ==="
    Remove-HumWatchService
    Write-Log "=== Uninstall complete ==="
    exit 0
}

# ---------------------------------------------------------------------------
#  INSTALL
# ---------------------------------------------------------------------------

Write-Log "=== Install started ==="
Write-Log "AppDir:  $AppDir"
Write-Log "Python:  $PythonPath"
Write-Log "NSSM:    $NssmPath"

# Validate prerequisites
if (-not (Test-Path $NssmPath))   { Write-Log "ERROR: NSSM not found at $NssmPath"; exit 1 }
if (-not (Test-Path $PythonPath)) { Write-Log "ERROR: Python not found at $PythonPath"; exit 1 }

# --- Step 1: Patch the ._pth file ---
# Do this FIRST, before service install.  Even if AppDirectory ends up wrong,
# the ".." entry makes "python -m agent.main" work from any CWD.
Patch-PythonPath

# --- Step 2: Remove any stale service ---
Remove-HumWatchService

# --- Step 3: Install the service via NSSM ---
Write-Log "Installing service via NSSM..."
$exitCode = Invoke-Nssm @("install", $ServiceName, $PythonPath, "-m agent.main")
if ($exitCode -ne 0) {
    Write-Log "ERROR: NSSM install failed (exit $exitCode)"
    exit 1
}

# Wait for Windows to register the service
Start-Sleep -Seconds 3
$svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Log "ERROR: Service not found after NSSM install."
    exit 1
}
Write-Log "Service registered."

# --- Step 4: Configure service parameters ---
Write-Log "Configuring service..."

$stdout = Join-Path $LogDir "humwatch-stdout.log"
$stderr = Join-Path $LogDir "humwatch-stderr.log"

# AppDirectory is the most critical setting.  NSSM defaults it to the
# directory containing the Application exe (python\), but we need the
# install root so that "python -m agent.main" finds the agent package.
$dirOk = Set-NssmParam "AppDirectory" @($AppDir)

# Stdout/stderr capture
Set-NssmParam "AppStdout"                   @($stdout)
Set-NssmParam "AppStderr"                   @($stderr)
Set-NssmParam "AppStdoutCreationDisposition" @("4")
Set-NssmParam "AppStderrCreationDisposition" @("4")

# Log rotation at 5 MB
Set-NssmParam "AppRotateFiles"  @("1")
Set-NssmParam "AppRotateOnline" @("1")
Set-NssmParam "AppRotateBytes"  @("5242880")

# Auto-restart on crash (5-second delay)
Set-NssmParam "AppExit"         @("Default", "Restart")
Set-NssmParam "AppRestartDelay" @("5000")

# --- Step 5: Verify AppDirectory (most common failure point) ---
try {
    $regDir = (Get-ItemProperty $ParamKey -ErrorAction Stop).AppDirectory
    Write-Log "Verified AppDirectory: $regDir"
    if ($regDir -ne $AppDir) {
        Write-Log "WARNING: AppDirectory still wrong ($regDir). Direct registry fix..."
        Set-ItemProperty -Path $ParamKey -Name AppDirectory -Value $AppDir -ErrorAction Stop
        $regDir = (Get-ItemProperty $ParamKey -ErrorAction Stop).AppDirectory
        if ($regDir -eq $AppDir) {
            Write-Log "AppDirectory corrected to: $regDir"
        } else {
            Write-Log "ERROR: AppDirectory could not be corrected. Got=$regDir Expected=$AppDir"
            Write-Log "The .._pth fallback should still allow the service to start."
        }
    }
} catch {
    Write-Log "WARNING: Could not verify AppDirectory: $_"
    Write-Log "The .._pth fallback should still allow the service to start."
}

# --- Step 6: Service metadata ---
Write-Log "Setting service metadata..."
sc.exe config $ServiceName start= auto obj= LocalSystem | Out-Null
sc.exe description $ServiceName "Local hardware monitoring agent (Static Hum Studio)" | Out-Null
Write-Log "Set auto-start and description."

# --- Step 7: Start the service ---
Write-Log "Starting service..."
$started = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        Start-Service $ServiceName -ErrorAction Stop
        Start-Sleep -Seconds 4
        $status = (Get-Service $ServiceName).Status
        Write-Log "Service status: $status (attempt $attempt)"
        if ($status -eq "Running") {
            $started = $true
            break
        }
        Write-Log "Service not running yet, retrying..."
        Start-Sleep -Seconds 2
    } catch {
        Write-Log "Start attempt $attempt failed: $_"
        if ($attempt -lt 3) { Start-Sleep -Seconds 3 }
    }
}

if (-not $started) {
    Write-Log "WARNING: Service did not reach Running state after 3 attempts."
    Write-Log "Try starting manually: sc.exe start HumWatch"
    # Don't exit 1 — the install itself succeeded, just the start failed.
    # The service will attempt to start on next reboot (StartType=auto).
}

Write-Log "=== Install complete ==="
exit 0
