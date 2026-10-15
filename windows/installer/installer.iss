; vbox Windows 侧载安装包 —— 「静默安装内核」（路线 A 的 core）
;
; 路线 A 说明（见 docs/网盘登录11问题_对齐修复清单_v1.3.md 第 8 章）：
;   最终交付物 vbox-setup.exe 是 .NET 壳（windows/setup-shell），本脚本编译产物
;   vbox-installer-core.exe 作为「内嵌资源」被壳释放并以静默模式执行，负责真正的
;   安装动作；所有既有安装逻辑（含常驻进程查杀）保持不变，仅新增进度上报钩子，
;   供壳轮询后驱动自绘 UI。
;
; 编译方式：ISCC.exe windows/installer/installer.iss
;   （GitHub Actions 工作流 .github/workflows/build-release-assets.yml 自动执行）
; 可选注入版本号：ISCC /DMyAppVersion=X.Y.Z windows/installer/installer.iss
; 无壳时单独调试 core（原生向导模式）：直接双击 vbox-installer-core.exe
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
; 路线 A：本产物是「静默安装内核」，由 .NET 壳内嵌；最终交付名 vbox-setup.exe
; 归壳所有（避免与外层同名冲突）。
OutputBaseFilename=vbox-installer-core
; 静默模式不需要向导配色；保留 modern 便于无壳时单独调试 core 的原生向导。
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
DisableProgramGroupPage=yes

; 升级时用 Windows Restart Manager 协助关闭占用安装目录内文件的进程
; （vbox.exe / 常驻 node.exe）。注意 Inno 6 没有 CloseApplicationsForce
; 指令；RM 对无窗口的 node.exe 常驻进程 Graceful 关闭会失败，真正的
; 兜底是下方 [Code] PrepareToInstall 的显式查杀。
CloseApplications=yes
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
; 常驻 node.exe（ND-02 Node 引擎内置 + Node 常驻系统）与内置 python.exe
; （ND-02-desktop CPython 子进程）在 vbox.exe 退出后仍按设计驻留后台。
; Inno 覆盖 {app}\noderuntime\node.exe、{app}\pyruntime\python.exe 时，Windows
; 拒绝删除正在运行的 exe → 「DeleteFile 失败；错误代码 5。拒绝访问」。
; 此处在复制文件前显式查杀：
;   - vbox.exe 按映像名连进程树强杀（/t 连带其子进程）；
;   - node.exe / python.exe 只按完整路径杀安装目录内的实例，不误伤系统其他
;     Node / Python 应用；
;   - 杀完等 800ms 让句柄释放，再由 ignoreversion 覆盖文件。
[Code]
// ══════════════════════════════════════════════════════════════════
//  进度上报通道（路线 A 新增 · 供 .NET 壳轮询读取，驱动自绘 UI）
//  ──────────────────────────────────────────────────────────────
//  路径由壳通过自定义参数 /VBOXPROG="<path>" 注入（Inno 6 支持
//  {param:VBOXPROG|} 常量；末尾竖线给出「参数缺失时的默认值=空串」，
//  避免无壳调试时 ExpandConstant 因参数不存在而抛异常）。
//  未注入时退化到临时目录下的固定文件名。
//  写入内容为单行 JSON：
//    · 阶段事件： {"stage":"extract","cur":-1,"max":-1}
//    · 字节进度： {"stage":"<当前阶段键>","cur":<n>,"max":<m>}（CurInstallProgressChanged，
//      阶段键粘性携带，避免覆写成空串导致页面不切卡）
//  壳解析后补上 "type":"progress" 再推给页面。
//
//  ⚠ 阶段键必须是纯 ASCII（prepare/extract/shortcut/done）：
//  Inno 的 SaveStringToFile 第二参数是 AnsiString，中文会按「系统 ANSI 代码页」
//  （中文 Windows = GBK）写出；而 .NET 壳用 File.ReadAllText 按 UTF-8 读取 →
//  中文阶段名变乱码 → 页面 STAGE_DEF 匹配失败 → 进度被压进「准备安装」的
//  0~8% 区间并封顶（实测卡 8%、卡片停在「1 准备安装」）。纯 ASCII 无编码歧义。
//  中文显示文案由 installer.html 内的映射表负责。
// ══════════════════════════════════════════════════════════════════
var
  { 是否已真正进入「已安装完成」状态；用于避免用户取消安装时误报“安装完成”。 }
  gInstallDone: Boolean;
  { 当前阶段键（粘性，纯 ASCII）。
    原因：Inno 的 CurInstallProgressChanged 在复制文件期间高频触发，每次都覆写
    同一份进度快照；若快照里 stage 留空，壳 150ms 轮询到的大概率是「字节进度」
    快照，页面就会永远停在上一阶段（实测卡在「准备安装」的 8% 上限）。
    因此把最近一次阶段名记住，每条快照都带上它。 }
  gStage: String;

function ProgPath(): String;
begin
  Result := ExpandConstant('{param:VBOXPROG|}');
  if Result = '' then
    Result := ExpandConstant('{tmp}\vbox-setup-progress.json');
end;

procedure WriteProgress(const Json: String);
begin
  { Append=False：整文件覆写，保证壳每次读到的是最新一条快照。
    单行小文件写入足够快，无需额外的原子替换。 }
  SaveStringToFile(ProgPath(), Json, False);
end;

{ 上报「阶段」——与定稿 UI 的 5 张步骤卡片对应（每步的基准百分比由壳/页面侧换算）。
  参数为纯 ASCII 阶段键（prepare/extract/shortcut/done），中文显示文案由页面映射。 }
procedure ReportStage(const Stage: String);
begin
  gStage := Stage; { 粘住当前阶段，供后续字节进度快照一并带上 }
  WriteProgress('{"stage":"' + Stage + '","cur":-1,"max":-1}');
end;

{ 上报「真实字节进度」——Inno 官方事件；静默（/VERYSILENT）模式下同样会被调用。
  若个别环境不触发，页面侧会退化为「按阶段推进的估算进度」（见 installer.html）。 }
procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  { 关键：带上 gStage，否则本快照会把阶段事件的 stage 覆盖成空串，页面永远不切卡。 }
  WriteProgress('{"stage":"' + gStage + '","cur":' + IntToStr(CurProgress) +
                ',"max":' + IntToStr(MaxProgress) + '}');
end;

// ── 升级 / 卸载前结束旧版进程（含 ND-02-desktop 内置 python.exe） ──────
//
// 背景：常驻 node.exe / python.exe 在 vbox.exe 退出后仍驻留后台，若安装/卸载
// 时未被杀干净，会锁死 {app} 下的 exe 文件（导致默认目录覆盖失败，用户只见
// 「安装不上」），且旧 node.exe 继续占用固定端口 58080-58084，新版 Node 引擎
// 起不来、登录/二维码请求全部打到旧进程（「正在生成二维码…」转圈）。
procedure KillVboxProcesses();
var
  AppDir: String;
  ResultCode: Integer;
begin
  AppDir := ExpandConstant('{app}');
  Log('KillVboxProcesses: AppDir=' + AppDir);
  Exec(ExpandConstant('{cmd}'), '/C taskkill /f /t /im vbox.exe',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Log('KillVboxProcesses: taskkill vbox.exe 退出码=' + IntToStr(ResultCode));
  { 按可执行路径杀 node/python。用 WMI Win32_Process 而非 Get-Process $_.Path：
    残留进程的 exe 文件被卸载删除后，Process.Path 可能为空导致漏杀；WMI 的
    ExecutablePath 记录的是进程创建时的映像路径，文件删除后仍可命中。
    匹配两处：① 安装目录（AppDir）；② 用户数据目录（*\com.vbox\vbox\*，
    Node 引擎常驻 node.exe 部署在 Roaming\com.vbox\vbox\noderuntime，升级/
    重装时必须一并杀掉，否则旧进程占住 58080 端口导致新版「Node 未就绪」）。
    Get-WmiObject 自 PowerShell 2.0（Win7）起可用。安全软件拦截 powershell
    时仅记日志不阻断安装。 }
  Exec('powershell.exe',
       '-NoProfile -ExecutionPolicy Bypass -Command ' +
       'Get-WmiObject Win32_Process -Filter "Name=''node.exe'' OR Name=''python.exe'' OR Name=''pythonw.exe''" | ' +
       'Where-Object { $_.ExecutablePath -like "' + AppDir + '\*" -or $_.ExecutablePath -like "*\com.vbox\vbox\*" } | ' +
       'ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; ' +
       'Start-Sleep -Milliseconds 800',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Log('KillVboxProcesses: powershell 退出码=' + IntToStr(ResultCode));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  ReportStage('prepare');
  Result := '';
  KillVboxProcesses();
end;

{ 阶段推进：ssInstall = 开始复制文件（含 Node 引擎，页面侧用字节进度切「部署 Node 引擎」）；
  ssPostInstall = 文件复制完成、开始写快捷方式 / 运行项。 }
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    ReportStage('extract');
  if CurStep = ssPostInstall then
  begin
    ReportStage('shortcut');
    gInstallDone := True;
  end;
end;

procedure DeinitializeSetup();
begin
  { 仅在真正安装完成后上报，避免用户中途取消时误报。 }
  if gInstallDone then
    ReportStage('done');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    KillVboxProcesses();
end;
