; Inno Setup script for Y-Node Desktop.
;
; The package is unsigned on purpose: Windows SmartScreen may warn about an
; unknown publisher, but the installer needs no code-signing certificate. It
; installs into Program Files for every user and asks for administrator rights,
; like a regular desktop application.
;
; Build: ISCC.exe /DMyVersion=1.0.0 installer.iss
#ifndef MyVersion
  #define MyVersion "1.1.0"
#endif

[Setup]
AppId={{9E7D6A4C-1F37-4D8C-9E61-3A6A5C0B7F21}
AppName=Y-Node
AppVersion={#MyVersion}
AppPublisher=Y-Node
AppPublisherURL=https://github.com/MrKsey/y-node
AppSupportURL=https://github.com/MrKsey/y-node
DefaultDirName={autopf}\Y-Node
DefaultGroupName=Y-Node
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\dist
OutputBaseFilename=y-node-desktop-{#MyVersion}-x64-setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\y_node_desktop.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\dist\windows\*"; DestDir: "{app}"; Excludes: "install-windows.ps1,uninstall-windows.ps1"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Y-Node"; Filename: "{app}\y_node_desktop.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Y-Node"; Filename: "{app}\y_node_desktop.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\y_node_desktop.exe"; Description: "Launch Y-Node"; Flags: nowait postinstall skipifsilent runasoriginaluser
; Explorer caches shortcut icons by path. A reinstall over the previous build
; kept the old square icon on the desktop and in the Start menu until the cache
; was rebuilt, so the installer asks the shell to refresh it. The entry has no
; Description on purpose: it runs silently and is not listed on the last page.
Filename: "{sys}\ie4uinit.exe"; Parameters: "-show"; Flags: runhidden nowait skipifsilent

[Code]
var
  RemoveSavedData: Boolean;

{ The per-user data directory holds the configuration, the identity, the peer
  lists and the exit profiles. It is not part of the installation, so the
  uninstaller has to ask about it: keeping it lets the next installation
  continue with the same address and peers, deleting it starts from scratch. }
function InitializeUninstall(): Boolean;
var
  Answer: Integer;
begin
  Result := True;
  RemoveSavedData := False;
  { An unattended removal must not wait for an answer: it keeps the data, which
    is the safe default, and a scripted purge passes its own switch. }
  if UninstallSilent() then
    Exit;
  { Nothing to ask when the app never stored anything: a fresh installation
    removed before its first run has no data directory. }
  if not DirExists(ExpandConstant('{userappdata}\Y-Node')) then
    Exit;
  Answer := MsgBox(
    'Delete all saved Y-Node data?' + #13#10 + #13#10 +
    'This removes the configuration, the private key, the peer lists and the saved exit profiles from:' + #13#10 +
    ExpandConstant('{userappdata}\Y-Node') + #13#10 + #13#10 +
    'Choose No to keep them: the next installation then starts with the same identity and peers.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2);
  RemoveSavedData := Answer = IDYES;
end;

{ Only a proxy that points at this app is touched. The window restores the
  saved state on a graceful shutdown; a forced stop during the uninstall skips
  that, and a browser must not keep pointing at a port that no longer exists. }
function LoopbackProxy: Boolean;
var
  Server: String;
begin
  Result := RegQueryStringValue(HKCU,
    'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    'ProxyServer', Server) and
    ((Pos('127.', Server) = 1) or (Pos('localhost', Server) = 1));
end;

procedure RestoreSystemProxy;
var
  ResultCode: Integer;
  Script: String;
begin
  if not LoopbackProxy then
    Exit;
  Script :=
    '$d=Join-Path $env:APPDATA ''Y-Node'';' +
    '$b=Join-Path $d ''system-proxy-backup.json'';' +
    '$k=''HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'';' +
    'if(Test-Path $b){$j=Get-Content $b -Raw|ConvertFrom-Json;' +
    'if($j.hasServer){Set-ItemProperty $k ProxyServer ([string]$j.server)}' +
    'else{Remove-ItemProperty $k ProxyServer -ErrorAction SilentlyContinue};' +
    'if($j.hasOverride){Set-ItemProperty $k ProxyOverride ([string]$j.override)}' +
    'else{Remove-ItemProperty $k ProxyOverride -ErrorAction SilentlyContinue};' +
    'Set-ItemProperty $k ProxyEnable ([int]$j.enable) -Type DWord}' +
    'else{Set-ItemProperty $k ProxyEnable 0 -Type DWord}';
  Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "' + Script + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

{ A running core keeps the system proxy on and the TUN adapter busy, and a
  running executable keeps its files locked: the installation directory cannot
  be replaced or removed while either process lives. The core restores the
  proxy and drops the tunnel on a graceful stop, so it is asked first; only a
  core that does not answer is killed. The window is a separate process and is
  stopped afterwards. }
procedure StopYNode;
var
  ResultCode: Integer;
  Script: String;
begin
  Script :=
    'try{Invoke-RestMethod -Method Post -Uri ''http://127.0.0.1:7799/v1/quit'' -TimeoutSec 15|Out-Null}catch{};' +
    '$i=0;while($i -lt 60 -and (Get-Process -Name ''y-node-core'' -ErrorAction SilentlyContinue)){Start-Sleep -Milliseconds 250;$i++};' +
    'Get-Process -Name ''y_node_desktop'',''y-node-core'' -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue;' +
    'Start-Sleep -Milliseconds 500';
  Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "' + Script + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

{ An update installs over the previous build, which may be running: it is
  stopped before the files are copied. A core that answered /v1/quit restores
  the system proxy itself; a core that had to be killed leaves it pointing at
  a port that is already gone, so the loopback proxy is restored here as well. }
function InitializeSetup(): Boolean;
begin
  StopYNode;
  RestoreSystemProxy;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    StopYNode;
    Exit;
  end;
  if CurUninstallStep <> usPostUninstall then
    Exit;
  RestoreSystemProxy;
  { The "Start with Windows" switch writes this entry; a leftover would make
    Windows launch a removed executable at every sign-in. }
  RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Y-Node');
  if RemoveSavedData then
    DelTree(ExpandConstant('{userappdata}\Y-Node'), True, True, True);
end;
