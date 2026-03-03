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
#  Helper: run NSSM via Start-Process (avoids PowerShell output-capture hangs)
# ---------------------------------------------------------------------------

function Invoke-Nssm {
    param([string[]]$Arguments)
    $p = Start-Process -FilePath $NssmPath -ArgumentList $Arguments `
         -Wait -NoNewWindow -PassThru
    return $p.ExitCode
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
        Write-Log "Deleting existing service..."
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
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

# Validate
if (-not (Test-Path $NssmPath))  { Write-Log "ERROR: NSSM not found at $NssmPath"; exit 1 }
if (-not (Test-Path $PythonPath)) { Write-Log "ERROR: Python not found at $PythonPath"; exit 1 }

# Remove any stale service
Remove-HumWatchService

# --- Step 1: Install the service via NSSM ---
Write-Log "Installing service via NSSM..."
$exitCode = Invoke-Nssm @("install", $ServiceName, $PythonPath, "-m agent.main")
Write-Log "NSSM install exit code: $exitCode"
Start-Sleep -Seconds 3

# Verify NSSM created the service
$svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Log "ERROR: NSSM install did not create the service."
    exit 1
}
Write-Log "NSSM service created successfully."

# --- Step 2: Configure via NSSM set commands ---
# Using NSSM's own set command is more reliable than direct registry writes.
# Direct Set-ItemProperty to HKLM service keys can fail silently under
# certain PowerShell/Inno-Setup execution contexts.

Write-Log "Configuring service settings via NSSM set..."

try {
    # Working directory -- CRITICAL: must be app root, not the python\ subfolder.
    # NSSM defaults AppDirectory to the directory of the Application exe, which
    # would be C:\HumWatch\python\ -- that breaks "python -m agent.main" because
    # the agent package lives in C:\HumWatch\agent\.
    $rc = Invoke-Nssm @("set", $ServiceName, "AppDirectory", $AppDir)
    Write-Log "Set AppDirectory=$AppDir (exit $rc)"

    # Logging
    $stdout = Join-Path $LogDir "humwatch-stdout.log"
    $stderr = Join-Path $LogDir "humwatch-stderr.log"
    Invoke-Nssm @("set", $ServiceName, "AppStdout", $stdout) | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppStderr", $stderr) | Out-Null
    Write-Log "Set log paths."

    # Log file creation disposition (4 = append)
    Invoke-Nssm @("set", $ServiceName, "AppStdoutCreationDisposition", "4") | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppStderrCreationDisposition", "4") | Out-Null

    # Log rotation (rotate at 5 MB)
    Invoke-Nssm @("set", $ServiceName, "AppRotateFiles", "1") | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppRotateOnline", "1") | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppRotateBytes", "5242880") | Out-Null
    Write-Log "Set log rotation settings."

    # Auto-restart on crash (5-second delay)
    Invoke-Nssm @("set", $ServiceName, "AppExit", "Default", "Restart") | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppRestartDelay", "5000") | Out-Null
    Write-Log "Set crash recovery settings."

} catch {
    Write-Log "WARNING: NSSM set commands failed: $_"
    Write-Log "Falling back to direct registry writes..."

    try {
        $ParamKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
        if (-not (Test-Path $ParamKey)) {
            New-Item -Path $ParamKey -Force | Out-Null
        }
        Set-ItemProperty -Path $ParamKey -Name AppDirectory                -Value $AppDir
        Set-ItemProperty -Path $ParamKey -Name AppStdout                   -Value (Join-Path $LogDir "humwatch-stdout.log")
        Set-ItemProperty -Path $ParamKey -Name AppStderr                   -Value (Join-Path $LogDir "humwatch-stderr.log")
        Set-ItemProperty -Path $ParamKey -Name AppStdoutCreationDisposition -Value 4
        Set-ItemProperty -Path $ParamKey -Name AppStderrCreationDisposition -Value 4
        Set-ItemProperty -Path $ParamKey -Name AppRotateFiles              -Value 1
        Set-ItemProperty -Path $ParamKey -Name AppRotateOnline             -Value 1
        Set-ItemProperty -Path $ParamKey -Name AppRotateBytes              -Value 5242880
        Set-ItemProperty -Path $ParamKey -Name AppExit                     -Value "Default Restart"
        Set-ItemProperty -Path $ParamKey -Name AppRestartDelay             -Value 5000
        Write-Log "Registry fallback succeeded."
    } catch {
        Write-Log "ERROR: Registry fallback also failed: $_"
    }
}

# --- Step 3: Service metadata via sc.exe ---
Write-Log "Setting service metadata..."
sc.exe config $ServiceName start= auto obj= LocalSystem | Out-Null
sc.exe description $ServiceName "Local hardware monitoring agent (Static Hum Studio)" | Out-Null
Write-Log "Set auto-start and description."

# --- Step 4: Verify final configuration ---
try {
    $ParamKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
    $regApp   = (Get-ItemProperty $ParamKey -ErrorAction SilentlyContinue).Application
    $regDir   = (Get-ItemProperty $ParamKey -ErrorAction SilentlyContinue).AppDirectory
    $regArgs  = (Get-ItemProperty $ParamKey -ErrorAction SilentlyContinue).AppParameters
    Write-Log "Verified Application:  $regApp"
    Write-Log "Verified AppDirectory: $regDir"
    Write-Log "Verified AppParameters:$regArgs"

    if ($regDir -ne $AppDir) {
        Write-Log "WARNING: AppDirectory mismatch. Expected=$AppDir Got=$regDir. Attempting fix..."
        Set-ItemProperty -Path $ParamKey -Name AppDirectory -Value $AppDir -ErrorAction SilentlyContinue
        Write-Log "AppDirectory corrected via direct registry write."
    }
} catch {
    Write-Log "WARNING: Could not verify registry settings: $_"
}

# --- Step 5: Start the service ---
Write-Log "Starting service..."
try {
    Start-Service $ServiceName -ErrorAction Stop
    Start-Sleep -Seconds 4
    $status = (Get-Service $ServiceName).Status
    Write-Log "Service status: $status"
    if ($status -ne "Running") {
        Write-Log "WARNING: Service did not reach Running state."
    }
} catch {
    Write-Log "ERROR starting service: $_"
    exit 1
}

Write-Log "=== Install complete ==="
exit 0
