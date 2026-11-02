; SUDOSEND Windows installer (Inno Setup 6)
; Built in CI:
;   ISCC /DAppVersion=0.2.1 /DSourceDir=... /DCliExe=... /DOutputDir=... /DIconFile=... sudosend.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{8F3C2A51-7B4D-4E2A-9C61-5D0E9B7A1F22}
AppName=SUDOSEND
AppVersion={#AppVersion}
AppVerName=SUDOSEND {#AppVersion}
AppPublisher=SUDOSOC
AppPublisherURL=https://seif.sudosoc.com
AppSupportURL=https://github.com/sudosoc/SUDOSEND/issues
DefaultDirName={autopf}\SUDOSEND
DefaultGroupName=SUDOSEND
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=sudosend-windows-x64-setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\sudosend.exe
UninstallDisplayName=SUDOSEND
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ChangesEnvironment=yes
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "firewall"; Description: "Allow SUDOSEND through Windows Firewall on private networks (recommended)"; GroupDescription: "Network:"
Name: "sendto"; Description: "Add SUDOSEND to the right-click ""Send to"" menu"; GroupDescription: "Shell:"
Name: "addpath"; Description: "Add the 'sudosend' command-line tool to PATH"; GroupDescription: "Command line:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#CliExe}"; DestDir: "{app}\cli"; DestName: "sudosend.exe"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\SUDOSEND"; Filename: "{app}\sudosend.exe"
Name: "{autodesktop}\SUDOSEND"; Filename: "{app}\sudosend.exe"; Tasks: desktopicon
Name: "{usersendto}\SUDOSEND"; Filename: "{app}\sudosend.exe"; Tasks: sendto

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""SUDOSEND"""; Flags: runhidden; Tasks: firewall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""SUDOSEND"" dir=in action=allow program=""{app}\sudosend.exe"" enable=yes profile=private,domain"; Flags: runhidden; Tasks: firewall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""SUDOSEND"" dir=in action=allow program=""{app}\cli\sudosend.exe"" enable=yes profile=private,domain"; Flags: runhidden; Tasks: firewall
Filename: "{app}\sudosend.exe"; Description: "{cm:LaunchProgram,SUDOSEND}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""SUDOSEND"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"

[Registry]
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\cli"; Tasks: addpath; Check: NeedsAddPath(ExpandConstant('{app}\cli'))

[Code]
const
  EnvKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function NeedsAddPath(Dir: string): Boolean;
var
  Current: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvKey, 'Path', Current) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Current) + ';') = 0;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Current, Dir: string;
  P: Integer;
begin
  if CurUninstallStep <> usPostUninstall then exit;
  Dir := ';' + ExpandConstant('{app}\cli');
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvKey, 'Path', Current) then
  begin
    P := Pos(Uppercase(Dir), Uppercase(Current));
    if P > 0 then
    begin
      Delete(Current, P, Length(Dir));
      RegWriteExpandStringValue(HKEY_LOCAL_MACHINE, EnvKey, 'Path', Current);
    end;
  end;
end;
