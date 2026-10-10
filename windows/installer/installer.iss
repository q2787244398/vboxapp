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

; 升级时用 Windows Restart Manager 关闭占用安装目录内文件的进程
; （vbox.exe / 常驻 node.exe）。force=yes 静默强关不弹询问；
; 配合下方 [Code] PrepareToInstall 的显式查杀双保险（RM 对无窗口的
; node.exe 常驻进程 Graceful 关闭会失败）。
CloseApplications=yes
CloseApplicationsForce=yes
RestartApplications=no

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

; ── 升级 / 卸载前结束旧版进程 ──────────────────────────────────────
; 常驻 node.exe（ND-02 Node 引擎内置 + Node 常驻系统）在 vbox.exe 退出后
; 仍按设计驻留后台。Inno 覆盖 {app}\noderuntime\node.exe 时，Windows 拒绝
; 删除正在运行的 exe → 「DeleteFile 失败；错误代码 5。拒绝访问」。
; 此处在复制文件前显式查杀：
;   - vbox.exe 按映像名连进程树强杀（/t 连带其子进程）；
;   - node.exe 只按完整路径杀安装目录内的实例，不误伤系统其他 Node 应用；
;   - 杀完等 800ms 让句柄释放，再由 ignoreversion 覆盖文件。
[Code]
procedure KillVboxProcesses();
var
  AppDir: String;
  ResultCode: Integer;
begin
  AppDir := ExpandConstant('{app}');
  Exec(ExpandConstant('{cmd}'), '/C taskkill /f /t /im vbox.exe',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('powershell.exe',
       '-NoProfile -ExecutionPolicy Bypass -Command ' +
       'Get-Process node -ErrorAction SilentlyContinue | ' +
       'Where-Object { $_.Path -like "' + AppDir + '\*" } | ' +
       'Stop-Process -Force; Start-Sleep -Milliseconds 800',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  KillVboxProcesses();
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    KillVboxProcesses();
end;
