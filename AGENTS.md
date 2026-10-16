# AGENTS.md

## 工程功能简述

VBox：多端聚合影视/网盘播放客户端。iOS 实现（Swift/SwiftUI）为唯一真相源，
Flutter 侧对齐实现 Android / macOS / Windows 三端。核心能力：站源爬虫
（Python/QuickJS/JSC 运行时）、网盘直链播放（百度/夸克/迅雷/UC/139 等，
含本机 Node 常驻链）、libmpv / ExoPlayer / AVPlayer 多内核播放、下载、
投屏、福利区等。

## 关键目录结构

```
lib/
  core/           基础设施（日志、网络、存储、常量、工具）
  data/           数据源（remote/local）、模型、仓库
  domain/         领域实体（cloud/player/spider/live/welfare/music…）与用例
  platform/       平台能力桥（player、download、spider、webview、node、runtime…）
  presentation/   UI（pages、shell、theme、widgets、ui_mode）
  main.dart       入口
windows/runner/   Windows 原生（播放器插件 player_plugin.cpp/.h、libmpv）
macos/Runner/     macOS 原生（PlayerPlugin.swift 等）
android/app/      Android 原生（JNI、node_bridge、Python 桥）
vbox/             iOS 参考实现（Swift，唯一真相源）
assets/           字体、品牌图、noderuntime、python-stdlib
scripts/          构建/打包/契约校验脚本
contract/         跨端契约（schema、abi、docs）
docs/             方案与对齐文档
```

## 约定

- 回复与代码注释使用中文。
- Flutter 侧改动须与 iOS 参考实现对齐；差异需在注释中写明对齐点。
- 日志统一走 `lib/core/utils/logger.dart` 的 `AppLog`（分类如
  `LogCategory.player` / `cloud` / `network`），不散落 `print`。
- 原生播放器日志经 EventChannel `com.vbox.player/player/events` 的
  `log` 事件上抛，由 `ChannelPlayer` 转入 `AppLog`（category=player）。

## 近期改动同步

- `lib/presentation/pages/cloud/native_cloud_drive_login_gateway.dart`：
  百度扫码 Cookie 补全对齐 iOS（5 端点 + `gettemplatevariable` 参与
  Set-Cookie 收集 + errno 日志）。
- `lib/data/datasources/remote/baidu_ibox_client.dart`：`fetchUserBdstoken`
  四层兜底补 errno 检查与分级日志，来源名对齐 iOS；`_webViewBdstoken`
  同时返回 WebView CookieJar 的 cookie，并对「WebView2 未就绪 / 载入失败」
  留痕；第 1 层响应非 JSON 时记录 status/content-type/长度（旧代码静默跳过
  是「取不到 bdstoken」的疑因）。
- `lib/platform/player/pan_player.dart`：`_saveBaiduBdstoken` 对齐 iOS
  `baiduPersistUserBdstoken`（合并 cookie + 更新登录态），并在 bdstoken /
  source / cookie 均无变化时跳过写盘。
- `lib/platform/player/channel_player.dart`：新增 `log` 事件处理，原生
  播放日志转 `AppLog`。
- `windows/runner/player_plugin.cpp/.h`：
  - **双渲染后端**：优先 OpenGL（离屏 FBO + `glReadPixels`），失败自动回退
    `MPV_RENDER_API_TYPE_SW` 软件渲染（`SW_SIZE/SW_FORMAT("bgra")/SW_STRIDE/SW_POINTER`），
    保证 GL 不可用（无显卡驱动 / 远程桌面 / 仅 GL 1.1）时仍有画面。
  - GL 能力预检 `ProbeGlCapability` **仅写日志、不作 `vo` 闸门**（避免预检误判
    导致本来能出画面却不出）。
  - 渲染链各失败路径日志、mpv 内部日志上抛、渲染失败非致命提示、引擎未释放
    前缓冲导致的丢帧留痕。
  - `RenderFrame` 拆出 `ResolveVideoSize` / `PublishFrame`，两后端共用上屏尾段。
- `macos/Runner/PlayerPlugin.swift`（对齐 Windows 同口径）：
  - **双渲染后端**：OpenGL（NSOpenGL 3.2 core + 离屏 FBO）失败自动回退
    `"sw"` 软件渲染。
  - 渲染链各失败路径日志（GL 入口缺失清单 / 像素格式 / render_context /
    FBO / 首帧）、mpv 内部日志上抛（`mpv_request_log_messages` +
    `log` 事件）、渲染失败非致命提示。
  - `renderMpvFrame` 拆出 `publishMpvFrame`，两后端共用上屏尾段。
- `android/app/src/main/kotlin/com/vbox/player/PlayerPlugin.kt`：
  新增 `log` 事件上报（open / 后端就绪 / 视频轨尺寸 / 播放错误 / 后端初始化
  失败），与 Windows/macOS 日志详细度对齐（Android 不走 mpv，无渲染后端问题）。
- `windows/runner/player_plugin.cpp`：mpv 初始化启用高质量渲染档位
  （`profile=high-quality`，旧版回退 `gpu-hq`），并显式钉住
  `correct-downscaling=yes` / `linear-downscaling=no` / `sigmoid-upscaling=yes`。
  修复「所有资源画质发虚、iOS 无此现象」：mpv 默认 scale/cscale=bilinear 且
  未开 correct-downscaling，窗口化缩放的画质明显劣于 iOS AVPlayer。
  macOS PlayerPlugin.swift 走同一 mpv 管线，后续可同步同参。
- `lib/presentation/pages/player/player_page.dart` /
  `lib/presentation/pages/search/search_page.dart`：调试日志导出在 Windows
  不走 SharePlus 系统共享面板（未打包应用必然弹「我们无法为你显示所有共享
  方法」），改为写入「下载」目录并在资源管理器中定位；失败退化为剪贴板。
- `windows/runner/baidu_token_bridge.{h,cpp}` + `windows/runner/webview2/`
  （WebView2 SDK 1.0.2903.40 头文件与静态加载器）+
  `windows/runner/player_plugin.{h,cpp}`（`com.vbox.player/cloud_bridge`
  通道）+ `lib/platform/webview/baidu_native_token_bridge.dart` +
  `lib/data/datasources/remote/baidu_ibox_client.dart`：
  普通百度网盘 bdstoken **原生 WebView2 桥**。凭据 Cookie 种入 WebView2
  持久化 Jar（`%APPDATA%\com.vbox\vbox\win_baidu_webview`）→ 真实浏览器栈
  导航 disk/main → 页面上下文 fetch gettemplatevariable（复刻 iOS
  WKWebView 系统网络栈信任度）→ Jar 全量 Cookie 回传合并回写凭据。
  owned 弹出窗口承载 Controller（3.1856 起为主窗口内 2x2 鼠标穿透形态，
  见下方 3.1854/3.1856 条目；不经 Flutter 插件 WebView，规避 3.1839 闪退 /
  3.1844 白屏路径）；全阶段看门狗，errno!=0 时种 Cookie 重导航一次后如实回传
  交 Dart 兜底链。
- `windows/runner/baidu_token_bridge.{h,cpp}`（3.1854 取号超时根因修复 +
  3.1856 修正）：
  - 宿主窗口「主窗口内 2x2 鼠标穿透」（3.1856，对齐 iOS「1x1 WKWebView
    addSubview 到可见 key window」）：主窗口客户区右下角内侧 2x2 owned 弹窗
    （`WS_EX_TRANSPARENT|WS_EX_NOACTIVATE|TOOLWINDOW`），`SW_SHOWNOACTIVATE`
    显示，Controller `IsVisible=TRUE`。3.1854 曾停靠「虚拟屏外」，但 Chromium
    `NativeWindowOcclusionTracker` 会把完全不在任何显示器区域内的窗口判定
    hidden/occluded → 3.1855 云电脑实测 NavigationCompleted 仍不触发（25s
    超时照旧）。挂在主窗口内则几何在屏幕内且 owned 弹窗恒在 owner 之上 →
    occlusion 判定可见。每条链路开始刷新停靠位（跟随主窗口移动/缩放）。
  - `ProcessFailed` 作废会话（`InvalidateSession`，浏览器主进程亡连环境一并
    重建）：修复渲染进程死亡后复用僵尸 COM 对象导致的「点重试闪退」；
    3.1856 起回调内只 `PostMessage(kProcessFailedMsg)`，销毁/回复延迟到
    消息循环执行（不在 WebView2 回调链内 Close/Release COM）。
  - 导航/脚本回调带代际校验：看门狗超时未停的挂起导航在新链路 Navigate 时
    补发的取消事件不再误杀新链路；迟到的 ExecuteScript 结果不再跨链路串扰。
  - `interactive` 交互验证模式：重试链路弹可见「百度安全验证」窗口（3 分钟
    看门狗 + 页面 Source 校验 + 关窗取消），人工过风控一次后 Jar 持久化；
    显示时摘除 `WS_EX_TRANSPARENT`（否则滑块/验证码无法交互），收尾恢复。
- `lib/data/datasources/remote/baidu_ibox_client.dart` /
  `lib/platform/webview/baidu_native_token_bridge.dart`：取号失败置位
  `_nextFetchInteractive`，用户点「重试」→ 第 0 层原生桥交互验证模式。
- `lib/presentation/pages/cloud/native_cloud_drive_login_gateway.dart`：
  重新扫码落库合并既有 `extra`（此前整体覆盖会把播放链回写的 `bdstoken`
  抹掉，形成「重登→兜底值丢失→再失败」死循环）。
- `windows/runner/player_plugin.{h,cpp}` + `lib/presentation/widgets/player/
  video_surface.dart`（3.1854 画质修复 + 3.1856 闪退/偏色修正）：
  - **按显示尺寸渲染**：`CopyPixelBuffer` 的引擎入参（纹理显示物理像素）
    原被忽略，现记录并在渲染线程取 `min(视频, 显示)` 为渲染目标——缩小由
    mpv 高质量缩放器（ewa_lanczossharp）完成，修复「4K 按原尺寸渲染、缩小
    全靠 Flutter bilinear」的发虚/摩尔纹（此前 mpv profile 修复无效的根因：
    FBO=视频原尺寸，mpv 内部缩放根本没参与）；回读带宽同步下降。纵横比上
    报始终用视频原始尺寸（与渲染目标解耦）。
  - **filterQuality 回退 low（3.1856 闪退修复）**：3.1854 曾改 medium，
    Windows 桌面引擎的外部纹理（PixelBufferTexture）无 mipmap 链，medium
    采样触发引擎 mipmap 路径后于 flutter_windows.dll 内 fastfail 闪退
    （3.1855 云电脑三连崩，WER BEX64 c0000409；iOS Metal 外部纹理路径无
    此问题）。按显示尺寸渲染后纹理 1:1 上屏，low 足够。
  - SW 软渲染色彩钉扎：`target-prim=bt.709` / `target-trc=srgb` /
    `tone-mapping=bt.2390`（软转换缺省仅 YUV→RGB 矩阵导致泛黄偏色）；
    3.1856 起 GL 路径同口径钉扎（消除 FBO 输出目标色彩空间歧义）。
  - **GL 回读颜色自检（3.1856 偏色根因修复）**：预检向 FBO 画已知纯色
    （红+绿双色）并回读比对 BGRA 字节序——虚拟化 GPU（真名不在黑名单的
    GRID/Paravirtual 等）`glReadPixels` 可能输出通道交换/错乱颜色，
    glFinish 修撕裂修不了颜色；黑名单只能枚举已知型号，实测回读字节才是
    确定性判据，不符即强制 SW（SW 色彩已钉扎）。
    `VBOX_FORCE_SW_RENDER=1` 环境变量强制 SW（逃生门）。
  - `FILE_LOADED` 上报视频色彩参数（pixfmt/primaries/gamma/hwdec），偏色
    类问题日志一眼定位 HDR/601/709 与解码路径。
- `windows/runner/baidu_token_bridge.cpp` + `scripts/bundle-webview2-windows.ps1`
  + `.github/workflows/build-release-assets.yml`（3.1857 百度取号「WebView2
  运行时不可用」根治 · 对齐 iOS「系统浏览器永远可用」）：
  - 3.1857 前原生桥依赖系统 Edge WebView2 Evergreen 运行时
    （`CreateCoreWebView2EnvironmentWithOptions(nullptr, ...)`）；精简系统/
    云电脑镜像未装时 `GetAvailableCoreWebView2BrowserVersionString` 返回
    `ERROR_FILE_NOT_FOUND`（0x80070002），取号在环境检测第一步即失败——与
    3.1854/3.1856 修复的「窗口可见性 / 导航超时」是两条无关的失败路径。
  - 修复为「随包内置固定版（Fixed Version）」：新增
    `WebView2BrowserExecutableDir()` 定位 `<exeDir>\webview2`，存在则离线加载
    （`CreateCoreWebView2EnvironmentWithOptions(fixed_dir, ...)`），否则回退
    系统 Evergreen 检测——未打包内置时行为与旧版一致，可安全回退。
  - `bundle-webview2-windows.ps1` 把 CI 构建机（windows-latest 预装 Edge
    WebView2）已就位的运行时复制为固定版到 `Release\webview2\`（排除
    Installer/SetupMetrics 缓存），installer.iss 递归打包自动携带。
  - **HRESULT 打印 bug 修复**：旧代码 `"0x" + std::to_string(十进制)` 把
    0x80070002 误打印成 `0x2147942402`（十进制 2147942402 = unsigned
    0x80070002），排查方向完全跑偏；新增 `HexHResult()` 统一按大写十六进制
    打印，8 处失败文案全部改用。
  - **原生日志回调上抛**：`BaiduTokenBridge` 新增 `SetLogCallback` + `EmitLog`
    （level ∈ debug/info/warn/error），PlayerPlugin 构桥后挂接 → `[baidu]`
    前缀经 `player/events` log 事件上抛 Dart AppLog。取号链路每一阶段
    （固定版检测/COM/环境/控制器/种 Cookie/导航/脚本/成功回传）都有留痕，
    满足「有错误就打印错误日志」的排查诉求。

## 日志事件契约（跨端）

`EventChannel com.vbox.player/player/events` 支持 `log` 类型：

```
{ "type": "log", "level": "info|warn|error|debug", "message": "…" }
```

Dart `ChannelPlayer._onEvent` 收到后转 `AppLog`（category=player，tag
`player-native`）。三端均已实现（Windows C++ / macOS Swift / Android Kotlin）。

## 已知待决问题

- 百度 `pcs_cookie` 在 iOS 与 Flutter 均无写入点，`pcs` 两端恒空，非差异。
- 渲染线程启用 `MPV_RENDER_PARAM_ADVANCED_CONTROL` 的帧回报契约已补齐：`MpvApi`
  现解析 `mpv_render_context_report_swap()`，OpenGL 与软件渲染路径均在
  `mpv_render_context_render()` 成功后回报一帧 swap，维持 mpv 帧节流/播速/timing
  正确（对齐 `windows/runner/player_plugin.{h,cpp}`）。
