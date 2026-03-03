; HumWatch — Inno Setup Installer Script
; A Static Hum Studio Production
;
; Built by scripts\build-installer.ps1 — do not compile manually.
; That script stages all required files into dist\stage\ first.
;
; Preprocessor defines supplied by build-installer.ps1:
;   /DMyAppVersion=0.9.6
;   /DStageDir=C:\...\dist\stage

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0-dev"
#endif

#ifndef StageDir
  #define StageDir "..\dist\stage"
#endif

#define MyAppName        "HumWatch"
#define MyAppPublisher   "Static Hum Studio"
#define MyAppURL         "https://github.com/StaticHumStudio/HumWatch"
#define MyAppExeName     "python\python.exe"
#define MyAppGUID        "{{A7B3C2D1-E4F5-4A6B-8C7D-9E0F1A2B3C4D}"
#define MyServiceName    "HumWatch"
#define MyDashboardURL   "http://localhost:9100"

[Setup]
AppId={#MyAppGUID}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName=C:\HumWatch
DefaultGroupName={#MyAppName}
AllowNoIcons=no
LicenseFile={#StageDir}\LICENSE
OutputDir={#StageDir}\..
OutputBaseFilename=HumWatch-Setup-v{#MyAppVersion}
SetupIconFile={#StageDir}\static\img\icon.ico
UninstallDisplayIcon={app}\static\img\icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardResizable=no
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
CloseApplications=yes
RestartIfNeededByRun=no
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
CreateUninstallRegKey=yes
UninstallDisplayName={#MyAppName} {#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut (opens dashboard)"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "firewallrule"; Description: "Add Windows &Firewall rule for port 9100 (required for multi-machine access)"; GroupDescription: "Network:"; Flags: checkedonce

[Dirs]
Name: "{app}"; Permissions: everyone-modify
Name: "{app}\logs"; Permissions: everyone-modify
Name: "{app}\data"; Permissions: everyone-modify

[Files]
; Python embeddable runtime + installed packages
Source: "{#StageDir}\python\*"; DestDir: "{app}\python"; Flags: recursesubdirs ignoreversion createallsubdirs

; HumWatch agent source
Source: "{#StageDir}\agent\*"; DestDir: "{app}\agent"; Flags: recursesubdirs ignoreversion createallsubdirs

; Dashboard static files
Source: "{#StageDir}\static\*"; DestDir: "{app}\static"; Flags: recursesubdirs ignoreversion createallsubdirs

; LibreHardwareMonitor DLLs
Source: "{#StageDir}\lib\*"; DestDir: "{app}\lib"; Flags: recursesubdirs ignoreversion createallsubdirs

; NSSM service manager
Source: "{#StageDir}\tools\nssm.exe"; DestDir: "{app}\tools"; Flags: ignoreversion

; Default config (only copy if not already present — preserves user settings on upgrade)
Source: "{#StageDir}\config.json"; DestDir: "{app}"; Flags: onlyifdoesntexist

; License and docs
Source: "{#StageDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme

; Service setup script (bundled, called during install)
Source: "service-setup.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion

[Icons]
Name: "{group}\Open HumWatch Dashboard"; Filename: "{sys}\cmd.exe"; Parameters: "/c start {#MyDashboardURL}"; IconFilename: "{app}\static\img\icon.ico"; Comment: "Open the HumWatch dashboard in your browser"
Name: "{group}\HumWatch Logs"; Filename: "{app}\logs"; Comment: "Browse HumWatch log files"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Open HumWatch Dashboard"; Filename: "{sys}\cmd.exe"; Parameters: "/c start {#MyDashboardURL}"; IconFilename: "{app}\static\img\icon.ico"; Comment: "Open the HumWatch dashboard in your browser"; Tasks: desktopicon

[Run]
; Install + start the Windows service
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NonInteractive -File ""{app}\tools\service-setup.ps1"" -Action install -AppDir ""{app}"""; \
  StatusMsg: "Installing HumWatch service..."; \
  Flags: runhidden waituntilterminated; \
  Description: "Install and start the HumWatch background service"

; Add firewall rule (optional task)
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NonInteractive -Command ""New-NetFirewallRule -DisplayName 'HumWatch' -Direction Inbound -Protocol TCP -LocalPort 9100 -Action Allow -Profile Any -ErrorAction SilentlyContinue"""; \
  StatusMsg: "Adding firewall rule..."; \
  Flags: runhidden waituntilterminated; \
  Tasks: firewallrule

; Offer to open the dashboard when done
Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start {#MyDashboardURL}"; \
  Description: "Open {#MyAppName} dashboard in browser"; \
  Flags: nowait postinstall skipifsilent unchecked

[UninstallRun]
; Stop and remove the Windows service
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NonInteractive -File ""{app}\tools\service-setup.ps1"" -Action uninstall -AppDir ""{app}"""; \
  Flags: runhidden waituntilterminated

; Remove firewall rule
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NonInteractive -Command ""Remove-NetFirewallRule -DisplayName 'HumWatch' -ErrorAction SilentlyContinue"""; \
  Flags: runhidden waituntilterminated

[UninstallDelete]
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\__pycache__"
; Note: config.json and humwatch.db are intentionally NOT deleted (preserve user data)
; User can manually delete {app} after uninstall if they want a clean removal

[Code]
// ── Upgrade detection ──────────────────────────────────────────────────────
function GetUninstallString(): string;
var
  sUnInstPath: string;
  sUnInstallString: string;
begin
  sUnInstPath := ExpandConstant('Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppGUID}_is1');
  sUnInstallString := '';
  if not RegQueryStringValue(HKLM, sUnInstPath, 'UninstallString', sUnInstallString) then
    RegQueryStringValue(HKCU, sUnInstPath, 'UninstallString', sUnInstallString);
  Result := sUnInstallString;
end;

function IsUpgrade(): Boolean;
begin
  Result := (GetUninstallString() <> '');
end;

function UnInstallOldVersion(): Integer;
var
  sUnInstallString: string;
  iResultCode: Integer;
begin
  Result := 0;
  sUnInstallString := GetUninstallString();
  if sUnInstallString <> '' then begin
    sUnInstallString := RemoveQuotes(sUnInstallString);
    if Exec(sUnInstallString, '/SILENT /NORESTART /SUPPRESSMSGBOXES', '', SW_HIDE, ewWaitUntilTerminated, iResultCode) then
      Result := iResultCode;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then begin
    if IsUpgrade() then begin
      UnInstallOldVersion();
    end;
  end;
end;

// ── Welcome page customization ────────────────────────────────────────────
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
