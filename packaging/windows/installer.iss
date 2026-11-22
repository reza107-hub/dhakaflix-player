; Inno Setup script for DhakaFlix Player (Windows x64).
; Built in CI:  iscc /DAppVersion=1.0.0 /DSourceDir=<flutter Release dir> packaging\windows\installer.iss
; Per-user install (no admin rights needed).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{2CE80121-835F-4E0A-AA68-A8AD9E25914F}
AppName=DhakaFlix Player
AppVersion={#AppVersion}
AppPublisher=DhakaFlix Player contributors
AppPublisherURL=https://github.com/reza107-hub/dhakaflix-player
AppSupportURL=https://github.com/reza107-hub/dhakaflix-player/issues
DefaultDirName={localappdata}\Programs\DhakaFlix Player
DefaultGroupName=DhakaFlix Player
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\dist
OutputBaseFilename=DhakaFlixPlayer-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\dhakaflix_player.exe
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"
Source: "..\..\NOTICE.md"; DestDir: "{app}"

[Icons]
Name: "{autoprograms}\DhakaFlix Player"; Filename: "{app}\dhakaflix_player.exe"
Name: "{autodesktop}\DhakaFlix Player"; Filename: "{app}\dhakaflix_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\dhakaflix_player.exe"; Description: "{cm:LaunchProgram,DhakaFlix Player}"; Flags: nowait postinstall skipifsilent
