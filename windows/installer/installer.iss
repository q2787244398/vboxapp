; vbox Windows 侧载安装包（S.7 命名：vbox-setup.exe）
; 编译方式：ISCC.exe windows/installer/installer.iss
;   （GitHub Actions 工作流 .github/workflows/build-release-assets.yml 自动执行）
; 可选注入版本号：ISCC /DMyAppVersion=X.Y.Z windows/installer/installer.iss
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

; 主程序可执行文件名：必须与 windows/CMakeLists.txt 的 BINARY_NAME 一致。
; Flutter 产物名为 vbox.exe；CMake target 名 "runner" 只体现在中间目录
; （build\windows\x64\runner\Release\），不是产物文件名。
#define MyAppExeName "vbox.exe"

[Setup]
; 固定 AppId（{{ 是 Inno 的转义），保证覆盖安装识别同一应用
AppId={{4A2B1C9E-7F63-4B0A-9D2E-1C8A0F6B4D51}
AppName=vbox
AppVersion={#MyAppVersion}
AppPublisher=vbox
DefaultDirName={autopf}\vbox
DefaultGroupName=vbox
; 安装程序自身图标（vbox 品牌图标，与桌面快捷方式一致）
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\app_icon.ico
Compression=lzma2
SolidCompression=yes
OutputDir=Output
OutputBaseFilename=vbox-setup
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
DisableProgramGroupPage=yes

; 安装界面简体中文（语言文件随仓库分发：languages/ChineseSimplified.isl，
; 来源 jrsoftware/issrc Files/Languages/ChineseSimplified.isl，UTF-8 BOM；
; 不依赖 Inno Setup 安装目录——choco 安装的 innosetup 缺 Languages 中文文件）
[Languages]
Name: "chinesesimp"; MessagesFile: "Languages\ChineseSimplified.isl"

[Files]
; 相对本文件（windows/installer/）两级的 build/windows/x64/runner/Release 全量文件
; （含 vbox.exe + Flutter DLL + libmpv-windows-*.dll，D28 随安装包分发）
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; vbox 品牌图标随包分发，供快捷方式 / 卸载列表使用
Source: "..\..\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\vbox"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{autodesktop}\vbox"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 vbox"; Flags: nowait postinstall skipifsilent
