; Inno Setup script for Dhara: a per-user installer.
;
; Made by tool\package.ps1, which passes the version, the folder to pack and
; where the installer goes. To compile by hand:
;   ISCC /DAppVersion=1.0.1 /DSourceDir=..\dist\Dhara-1.0.1 /DOutputDir=..\dist installer\dhara.iss
;
; What it does on the PC it runs on, and nothing else:
;   - copies the app to %LOCALAPPDATA%\Programs\Dhara
;   - adds a Start Menu shortcut, and a desktop shortcut if asked for
;   - registers its uninstaller for this user (HKCU)
; It never asks for admin rights and has no way to: no service, no start-up
; entry, no scheduled task, no updater, no registry key of its own, nothing
; under Program Files or HKLM, and nothing is downloaded.
;
; test\security\code_rules_test.dart fails if this file is given any of that.

#ifndef AppVersion
  #error Pass /DAppVersion=<x.y.z>
#endif
#ifndef SourceDir
  #error Pass /DSourceDir=<the folder tool\package.ps1 staged>
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

; /DTestCopy makes the installer of a build that keeps its data in a
; scratch folder: another name, another id, so it installs beside the real
; app and never over it.
#ifdef TestCopy
  #define AppName "Dhara Test"
  #define AppId "{{B39A315B-ED1C-4708-A50E-E4AF6AE1DC9E}"
  #define SetupName "Dhara-Test-Setup-" + AppVersion
#else
  #define AppName "Dhara"
  #define AppId "{{C20665BD-4919-47A4-9DE8-CA94A6D0CF47}"
  #define SetupName "Dhara-Setup-" + AppVersion
#endif

[Setup]
; Never change the id: it is how a newer installer finds the older install.
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup

; For this user only. With "lowest" the installer runs as the user who
; started it and {autopf} is %LOCALAPPDATA%\Programs.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
; One place, not asked for: an update clears the app's files there first.
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; An update over a running app asks to close it; it is not started again
; behind the user's back.
CloseApplications=yes
RestartApplications=no

Compression=lzma2/ultra64
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#SetupName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\dhara.exe
UninstallDisplayName={#AppName}
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; An update leaves nothing of the older version behind: every file of the
; app is in the installer, and the user's data is not in this folder.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\dhara.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\dhara.exe"; Tasks: desktopicon

[Run]
; Offered on the last page, never done by itself (not at all in a silent
; install).
Filename: "{app}\dhara.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Uninstalling removes the app's folder and its shortcuts. The library, the
; settings and the pictures (%APPDATA%\com.dhara\dhara) and the TMDB key
; (Windows Credential Manager, "Dhara/tmdb") stay: the README says how to
; remove them by hand.
