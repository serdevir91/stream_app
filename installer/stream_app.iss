[Setup]
AppName=StreamApp
AppVersion=1.0.1
AppPublisher=StreamApp
AppPublisherURL=https://github.com/serdevir91/stream_app
DefaultDirName={autopf}\StreamApp
DefaultGroupName=StreamApp
OutputDir=..\output
OutputBaseFilename=StreamApp-Setup-v1.0.1
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
Source: "..\build\windows\x64\runner\Release\stream_app.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\webview_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\dartjni.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\StreamApp"; Filename: "{app}\stream_app.exe"
Name: "{group}\{cm:UninstallProgram,StreamApp}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\StreamApp"; Filename: "{app}\stream_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\stream_app.exe"; Description: "{cm:LaunchProgram,StreamApp}"; Flags: nowait postinstall skipifsilent
