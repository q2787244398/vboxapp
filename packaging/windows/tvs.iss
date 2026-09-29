; TVS Windows 安装包脚本（Inno Setup 6）
;
; 由 CI 调用：
;   ISCC.exe /DMyAppVersion=1.2.2 /DSourceDir=<构建输出目录> /DOutputDir=<dist目录> tvs.iss
;
; 默认值仅用于本地手动编译时兜底。

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\flutter\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; 注意：Inno Setup 中 "{{" 转义为字面量 "{"，固定 AppId 才能正确覆盖安装/卸载
AppId={{8F3A2C1E-5B47-4D9A-9E21-7C6F0B4A3D18}
AppName=TVS
AppVersion={#MyAppVersion}
AppVerName=TVS {#MyAppVersion}
AppPublisher=TVS
AppPublisherURL=https://github.com/q2787244398/vboxapp
DefaultDirName={autopf}\TVS
DefaultGroupName=TVS
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename=TVS-{#MyAppVersion}-windows-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 默认按用户级安装（不强制提权），需要时可在向导里切换为全机安装
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\tvs.exe
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter Windows 构建输出：tvs.exe + 若干 DLL + data/ 资源目录
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\TVS"; Filename: "{app}\tvs.exe"
Name: "{group}\{cm:UninstallProgram,TVS}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\TVS"; Filename: "{app}\tvs.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\tvs.exe"; Description: "{cm:LaunchProgram,TVS}"; Flags: nowait postinstall skipifsilent
