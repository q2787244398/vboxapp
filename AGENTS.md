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

## 日志事件契约（跨端）

`EventChannel com.vbox.player/player/events` 支持 `log` 类型：

```
{ "type": "log", "level": "info|warn|error|debug", "message": "…" }
```

Dart `ChannelPlayer._onEvent` 收到后转 `AppLog`（category=player，tag
`player-native`）。三端均已实现（Windows C++ / macOS Swift / Android Kotlin）。

## 已知待决问题

- 百度 `pcs_cookie` 在 iOS 与 Flutter 均无写入点，`pcs` 两端恒空，非差异。
- 渲染线程启用了 `MPV_RENDER_PARAM_ADVANCED_CONTROL`，但未调用 mpv 契约要求的
  `mpv_render_context_report_swap()`（帧已呈现回报），可能影响帧节流/画面刷新
  时机；`MpvApi` 尚未解析该符号，待确认是否补齐。
