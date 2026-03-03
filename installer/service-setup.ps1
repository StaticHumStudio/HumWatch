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

# ── Logging helper ────────────────────────────────────────────────────────

$LogFile = Join-Path $LogDir "service-setup.log"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# ── Remove existing service ───────────────────────────────────────────────

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

# ── UNINSTALL ─────────────────────────────────────────────────────────────

if ($Action -eq "uninstall") {
    Write-Log "=== Uninstall started ==="
    Remove-HumWatchService
    Write-Log "=== Uninstall complete ==="
    exit 0
}

# ── INSTALL ───────────────────────────────────────────────────────────────

Write-Log "=== Install started ==="
Write-Log "AppDir:  $AppDir"
Write-Log "Python:  $PythonPath"
Write-Log "NSSM:    $NssmPath"

# Validate
if (-not (Test-Path $NssmPath))  { Write-Log "ERROR: NSSM not found at $NssmPath"; exit 1 }
if (-not (Test-Path $PythonPath)) { Write-Log "ERROR: Python not found at $PythonPath"; exit 1 }

# Remove any stale service
Remove-HumWatchService

# Install via NSSM
Write-Log "Installing service via NSSM..."
Start-Process -FilePath $NssmPath -ArgumentList "install",$ServiceName,$PythonPath,"-m agent.main" -Wait -NoNewWindow -PassThru | Out-Null
Start-Sleep -Seconds 2

# Verify NSSM created the service
$svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Log "ERROR: NSSM install did not create the service."
    exit 1
}
Write-Log "NSSM service created successfully."

# Fix registry: NSSM install doesn't always add the service name to ImagePath
# (PowerShell calling convention issue). Set it directly.
$SvcKey    = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
$ParamKey  = "$SvcKey\Parameters"

if (-not (Test-Path $ParamKey)) {
    New-Item -Path $ParamKey -Force | Out-Null
    Write-Log "Created Parameters registry key."
}

Write-Log "Writing service registry values..."

# ImagePath must be: "<nssm.exe path>" <ServiceName>
Set-ItemProperty -Path $SvcKey -Name ImagePath -Value "`"$NssmPath`" $ServiceName"

# NSSM application parameters
Set-ItemProperty -Path $ParamKey -Name Application     -Value $PythonPath
Set-ItemProperty -Path $ParamKey -Name AppParameters   -Value "-m agent.main"
Set-ItemProperty -Path $ParamKey -Name AppDirectory    -Value $AppDir

# Logging (log rotation at 5 MB)
Set-ItemProperty -Path $ParamKey -Name AppStdout              -Value "$LogDir\humwatch-stdout.log"
Set-ItemProperty -Path $ParamKey -Name AppStderr              -Value "$LogDir\humwatch-stderr.log"
Set-ItemProperty -Path $ParamKey -Name AppStdoutCreationDisposition -Value 4
Set-ItemProperty -Path $ParamKey -Name AppStderrCreationDisposition -Value 4
Set-ItemProperty -Path $ParamKey -Name AppRotateFiles         -Value 1
Set-ItemProperty -Path $ParamKey -Name AppRotateOnline        -Value 1
Set-ItemProperty -Path $ParamKey -Name AppRotateBytes         -Value 5242880

# Auto-restart on crash (5 second delay)
Set-ItemProperty -Path $ParamKey -Name AppExit          -Value "Default Restart"
Set-ItemProperty -Path $ParamKey -Name AppRestartDelay  -Value 5000

# Service metadata
sc.exe config $ServiceName start= auto obj= LocalSystem | Out-Null
sc.exe description $ServiceName "Local hardware monitoring agent (Static Hum Studio)" | Out-Null

# Verify registry looks correct
$imagePath = (Get-ItemProperty $SvcKey).ImagePath
$appPath   = (Get-ItemProperty $ParamKey -ErrorAction SilentlyContinue).Application
$appDir    = (Get-ItemProperty $ParamKey -ErrorAction SilentlyContinue).AppDirectory
Write-Log "Verified ImagePath:   $imagePath"
Write-Log "Verified Application: $appPath"
Write-Log "Verified AppDirectory:$appDir"

if ($imagePath -notmatch [regex]::Escape($ServiceName)) {
    Write-Log "WARNING: ImagePath does not contain service name -- NSSM may not start correctly."
}
if ($appDir -ne $AppDir) {
    Write-Log "WARNING: AppDirectory mismatch. Expected: $AppDir, Got: $appDir"
    Set-ItemProperty -Path $ParamKey -Name AppDirectory -Value $AppDir
    Write-Log "AppDirectory corrected."
}

# Start the service
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
