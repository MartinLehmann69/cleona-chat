; Cleona Chat — Inno Setup Script
; Builds a Windows installer from the Flutter release output.
;
; Required defines (passed via /D on iscc command line):
;   AppVersion    e.g. "3.1.147"
;   BuildDir      e.g. "C:\Users\Cleona\Cleona\build\windows\x64\runner\Release"
;   OutputDir     e.g. "C:\Users\Cleona"
;   OutputName    e.g. "cleona-chat-3.1.147-beta-windows-x64-setup"

[Setup]
AppId={{8F4A9C2E-7B3D-4E1F-A5C8-2D9E6F0B1A4C}
AppName=Cleona Chat
AppVersion={#AppVersion}
AppVerName=Cleona Chat {#AppVersion}
AppPublisher=Cleona Project
AppPublisherURL=https://cleona.org
DefaultDirName={localappdata}\Cleona Chat
DefaultGroupName=Cleona Chat
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile={#BuildDir}\data\flutter_assets\assets\app_icon.ico
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
Name: "autostart"; Description: "Cleona Chat beim Windows-Start automatisch starten"; GroupDescription: "Autostart:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Cleona Chat"; Filename: "{app}\cleona.exe"; IconFilename: "{app}\cleona.exe"
Name: "{group}\Cleona Chat deinstallieren"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Cleona Chat"; Filename: "{app}\cleona.exe"; Tasks: desktopicon

[Registry]
; S367: der Daemon liegt in {app}\bin\ — `dart build cli` bettet den Pfad
; seiner Ablage-Bibliothek als ..\lib\ RELATIV ZUR BINAERDATEI ein. Aus
; {app} heraus zeigte das eine Ebene zu hoch, und der Daemon endete beim
; Oeffnen der Ablage mit Exit 0 — fuer die GUI ununterscheidbar von
; "laeuft, oeffnet nur keinen Socket". Die [Files]-Zeile oben nimmt das
; Unterverzeichnis ueber `recursesubdirs` ohnehin mit.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "CleonaDaemon"; ValueData: """{app}\bin\cleona-daemon.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\cleona.exe"; Description: "Cleona Chat starten"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/IM cleona-daemon.exe /F"; Flags: runhidden; RunOnceId: "KillDaemon"
Filename: "taskkill"; Parameters: "/IM cleona.exe /F"; Flags: runhidden; RunOnceId: "KillGui"

[Code]
var
  ResultCode: Integer;

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
      '/d /s /c ""' + ExpandConstant('{app}\cleona-firewall.cmd') + '" ' + Action + ' "' + Daemon + '""',
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
    Exec('taskkill', '/IM cleona-daemon.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('taskkill', '/IM cleona.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
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
