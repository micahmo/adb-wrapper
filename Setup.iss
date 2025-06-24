#define MyAppName "adb-wrapper"
#define MyAppExeName "adb_wrapper.exe"
#define MyAppVersion GetEnv("VERSION")
#define MyAppPublisher "Micah Morrison"
#define MyAppURL "https://github.com/micahmo/adb-wrapper"
; This is relative to SourceDir
#define RepoRoot "..\..\..\..\.."

[Setup]
AppId={{9DAE46CC-0D30-4908-AB40-8494C48D1A5C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
; Start menu folder
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
SourceDir=build\windows\x64\runner\Release\
OutputDir={#RepoRoot}
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputBaseFilename={#MyAppName}-setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "*"; DestDir: "{app}"; Flags: recursesubdirs

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch adb-wrapper"; Flags: nowait postinstall skipifsilent
