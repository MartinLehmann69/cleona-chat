; Cleona Chat — Inno Setup Script
; Builds a Windows installer from the Flutter release output.
;
; Required defines (passed via /D on iscc command line):
;   AppVersion    e.g. "3.1.147"
;   BuildDir      e.g. "C:\Users\Cleona\Cleona\build\windows\x64\runner\Release"
;   OutputDir     e.g. "C:\Users\Cleona"
;   OutputName    e.g. "cleona-chat-3.1.147-beta-windows-x64-setup"

;   Channel       "beta" or "live" (default beta). v4_2 section 26.2: beta and
;                 live install side by side, each with its own identity. Live
;                 keeps the identity every earlier setup carried.

#ifndef Channel
  #define Channel "beta"
#endif
#if Channel == "live"
  #define ProductName "Cleona Chat"
  #define ProductAppId "{{8F4A9C2E-7B3D-4E1F-A5C8-2D9E6F0B1A4C}"
  #define AutostartValue "CleonaDaemon"
  #define IconAsset "app_icon.ico"
#else
  #define ProductName "Cleona Beta"
  #define ProductAppId "{{C2D7E1A4-3F96-4B58-9E0D-71A6B4F2C853}"
  #define AutostartValue "CleonaBetaDaemon"
  #define IconAsset "app_icon_beta.ico"
#endif

[Setup]
AppId={#ProductAppId}
AppName={#ProductName}
AppVersion={#AppVersion}
AppVerName={#ProductName} {#AppVersion}
AppPublisher=Cleona Project
AppPublisherURL=https://cleona.org
DefaultDirName={localappdata}\{#ProductName}
DefaultGroupName={#ProductName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile={#BuildDir}\data\flutter_assets\assets\{#IconAsset}
UninstallDisplayIcon={app}\cleona.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
MinVersion=10.0
CloseApplications=force
RestartApplications=no

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
german.FirewallStatus=Windows-Firewall: eingehende Verbindungen für Cleona erlauben (einmalige Zustimmung) ...
english.FirewallStatus=Windows Firewall: allowing incoming connections for Cleona (one consent) ...

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "{#ProductName} beim Windows-Start automatisch starten"; GroupDescription: "Autostart:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#ProductName}"; Filename: "{app}\cleona.exe"; IconFilename: "{app}\data\flutter_assets\assets\{#IconAsset}"
Name: "{group}\{#ProductName} deinstallieren"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#ProductName}"; Filename: "{app}\cleona.exe"; IconFilename: "{app}\data\flutter_assets\assets\{#IconAsset}"; Tasks: desktopicon

[Registry]
; S367: der Daemon liegt in {app}\bin\ — `dart build cli` bettet den Pfad
; seiner Ablage-Bibliothek als ..\lib\ RELATIV ZUR BINAERDATEI ein. Aus
; {app} heraus zeigte das eine Ebene zu hoch, und der Daemon endete beim
; Oeffnen der Ablage mit Exit 0 — fuer die GUI ununterscheidbar von
; "laeuft, oeffnet nur keinen Socket". Die [Files]-Zeile oben nimmt das
; Unterverzeichnis ueber `recursesubdirs` ohnehin mit.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AutostartValue}"; ValueData: """{app}\bin\cleona-daemon.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\cleona.exe"; Description: "{#ProductName} starten"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Only this installation's processes: the same image names run from the other
; channel's folder next to it.
Filename: "powershell.exe"; Parameters: "-NoProfile -NonInteractive -Command ""Get-Process cleona,cleona-daemon -EA SilentlyContinue | Where-Object {{ $_.Path -like '{app}\*' } | Stop-Process -Force"""; Flags: runhidden; RunOnceId: "KillOwn"

[Code]
var
  ResultCode: Integer;

procedure StopProcessesIn(const Folder: String);
begin
  Exec('powershell.exe', '-NoProfile -NonInteractive -Command "Get-Process cleona,cleona-daemon -EA SilentlyContinue | Where-Object { $_.Path -like ''' + Folder + '\*'' } | Stop-Process -Force"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

#if Channel != "live"
{ A former beta installation under "Cleona Chat" (every setup before the split,
  51 of 51 releases were beta). It would stay in the start menu, and its
  autostart would run the old daemon against the same profile. Its uninstaller
  has no step that touches the profile. A folder marked live is the other
  channel's and stays. }
procedure RemoveFormerBetaInstallation;
var
  OldDir, Channel, Uninstaller: String;
  Ansi: AnsiString;
begin
  OldDir := ExpandConstant('{localappdata}\Cleona Chat');
  if LoadStringFromFile(OldDir + '\data\channel', Ansi) then
  begin
    Channel := Trim(String(Ansi));
    if Channel = 'live' then Exit;
  end;
  if not RegQueryStringValue(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4A9C2E-7B3D-4E1F-A5C8-2D9E6F0B1A4C}_is1',
      'UninstallString', Uninstaller) then Exit;
  StopProcessesIn(OldDir);
  Exec(RemoveQuotes(Uninstaller), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Log(Format('Former beta installation removed: exit %d', [ResultCode]));
  RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'CleonaDaemon');
end;
#endif

{ The inbound firewall rule of the daemon (v4_2 section 22, "Windows
  Desktop"; S407). The setup installs without administrator rights; this is
  the ONE step that asks for them. It runs the helper shipped in the bundle,
  cleona-firewall.cmd - the same one the app's "Allow in firewall" runs -
  so there is one definition of the rule: inbound allow for
  bin\cleona-daemon.exe, UDP and TCP, all network profiles, after removing
  every inbound rule naming the program (including the blocking "Query User"
  rules Windows leaves when its own prompt was cancelled).
  A declined consent does not stop the installation: the app checks the
  rule at every start and offers the same step. }
procedure RunFirewallHelper(const Action: String);
var
  Code: Integer;
  Daemon: String;
begin
  Daemon := ExpandConstant('{app}\bin\cleona-daemon.exe');
  { Through cmd.exe /d /s /c ""<helper>" <action> "<daemon>"": started
    directly with "runas", Windows runs the .cmd as cmd.exe /C "<helper>"
    <action> "<daemon>", cmd.exe strips the first and last quote, the path
    breaks at the space of "Cleona Chat" and nothing is set (exit 1,
    measured on the lab VM 14.10.2026). }
  if ShellExec('runas', ExpandConstant('{cmd}'),
      '/d /s /c ""' + ExpandConstant('{app}\cleona-firewall.cmd') + '" ' + Action + ' "' + Daemon + '" {#Channel}"',
      ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) then
    Log(Format('Firewall helper "%s" ended with %d', [Action, Code]))
  else
    { One line: a line beginning with "[" is read as a section tag, even
      inside [Code]. }
    Log(Format('Firewall helper "%s" not run: %s (%d)', [Action, SysErrorMessage(Code), Code]));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    { Only this installation's processes; the other channel keeps running. }
    StopProcessesIn(ExpandConstant('{app}'));
#if Channel != "live"
    RemoveFormerBetaInstallation;
#endif
    Sleep(1000);
  end;
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := CustomMessage('FirewallStatus');
    RunFirewallHelper('allow');
  end;
end;

{ Uninstall removes the rule, elevated as well. It may fail (consent
  declined): a rule naming a program that no longer exists admits nothing. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RunFirewallHelper('remove');
end;
