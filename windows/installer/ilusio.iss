; ilusio.iss — instalador do Ilusio para Windows (Inno Setup 6), sem assinatura
; Uso: iscc /DVersion=0.1.1 windows\installer\ilusio.iss   (espera build\dist\Ilusio e build\ilusio.ico)
#ifndef Version
  #define Version "0.0.0"
#endif

[Setup]
; AppId fixo: atualizações substituem a instalação anterior
AppId={{31DB57F1-C36F-4601-906A-057992DD131A}
AppName=Ilusio
AppVersion={#Version}
AppPublisher=Ilusio
AppPublisherURL=https://github.com/mvtiburcio/teleporte-instantaneo
DefaultDirName={autopf}\Ilusio
DisableProgramGroupPage=yes
; por usuário, sem UAC (a Ilusio Camera, quando vier, pede admin)
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SourceDir=..\..
OutputDir=build\installer
OutputBaseFilename=Ilusio-Setup-{#Version}
SetupIconFile=build\ilusio.ico
UninstallDisplayIcon={app}\Ilusio.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
LicenseFile=LICENSE

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktop"; Description: "Criar atalho na área de trabalho"; Flags: unchecked

[Files]
Source: "build\dist\Ilusio\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Ilusio"; Filename: "{app}\Ilusio.exe"
Name: "{autodesktop}\Ilusio"; Filename: "{app}\Ilusio.exe"; Tasks: desktop

[Run]
Filename: "{app}\Ilusio.exe"; Description: "Abrir o Ilusio"; Flags: nowait postinstall skipifsilent

[InstallDelete]
; versão nova do PyInstaller muda os nomes em _internal: sem isso sobram arquivos velhos
Type: filesandordirs; Name: "{app}\_internal"
