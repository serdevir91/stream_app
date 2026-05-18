[Setup]
AppName=StreamApp
AppVersion=1.0.3
AppPublisher=StreamApp
AppPublisherURL=https://github.com/serdevir91/stream_app
DefaultDirName={autopf}\StreamApp
DefaultGroupName=StreamApp
OutputDir=..\output
OutputBaseFilename=StreamApp-Setup-v1.0.3
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\stream_app.exe


[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\StreamApp"; Filename: "{app}\stream_app.exe"
Name: "{group}\{cm:UninstallProgram,StreamApp}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\StreamApp"; Filename: "{app}\stream_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\stream_app.exe"; Description: "{cm:LaunchProgram,StreamApp}"; Flags: nowait postinstall skipifsilent
