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
ArchitecturesInstallIn64BitModeOnly=x64compatible
WizardStyle=modern
MinVersion=10.0
CloseApplications=force
RestartApplications=no

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

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
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "CleonaDaemon"; ValueData: """{app}\cleona-daemon.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\cleona.exe"; Description: "Cleona Chat starten"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/IM cleona-daemon.exe /F"; Flags: runhidden; RunOnceId: "KillDaemon"
Filename: "taskkill"; Parameters: "/IM cleona.exe /F"; Flags: runhidden; RunOnceId: "KillGui"

[Code]
var
  ResultCode: Integer;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    Exec('taskkill', '/IM cleona-daemon.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('taskkill', '/IM cleona.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1000);
  end;
end;
