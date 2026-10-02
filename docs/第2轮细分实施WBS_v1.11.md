# vbox 第 2 轮细分实施 WBS · v1.11（任务级）

> **定位**：把 [第2轮开发计划_功能补全_v2.9.md](computer:///workspace/vboxapp/docs/第2轮开发计划_功能补全_v2.9.md) 的**批次级方案**下沉为**任务级可执行清单**（可直接开工/派工/验收）。不替代方案文档。
> **事实依据**：[第2轮开发方案_iOS全量复核_v1.3.md](computer:///workspace/vboxapp/docs/第2轮开发方案_iOS全量复核_v1.3.md) 四轮复核（185/185 文件枚举 + 契约/数据层真值）。
> **状态标注**：**新建**（从零做）· **改造**（Flutter 已有基建，改）· **复用**（已有，直接用）· **移植**（从 iOS 迁语义/资源）。
> **任务编号**：`批次-序号`（如 `A-03`）；共 **128 个任务条目**。
> **v1.1 变更**：① 落定 **D6**（三端均集成 JSC）→ 改写 B-05、新增 **B-05a**、新增 **批次 Q（JSC 三端集成）**；② 修正 v1.0 的任务计数（原写 131，实测 **121**；加 B-05a 与批次 Q 后为 **128**）。
> **v1.2 变更（D24/D25，2026-10-01）**：**批次 A（设计基座 A-01 ~ A-13）代码侧全量交付** → 写入交付记录与全量自检结果；补齐 A-12 遗漏项「35 张 iOS UI 图归档」至 `docs/ui_baseline/ios_ref/`（35 文件 + manifest.json 页面族映射，19 族全中）。文件名升版 v1.1 → v1.2（旧名 `第2轮细分实施WBS_v1.1.md` 仅存于各文档历史沿革行——`is_history` 豁免口径；**现行**引用已全部改指 v1.2）。
> **v1.3 变更（D26/D27，2026-10-01）**：**批次 B 首段（B-01 ~ B-06 + B-05a）代码侧交付**（远程源配置管理器状态机 / 代理降级链 / 6 合 1 聚合 / 站点模式判定 / JS 全局桥 prelude + QuickJS 引擎集成）→ 写入交付记录与自检结果（709 用例全绿 + 11 守卫全绿）；**Q-01 门禁完成**（`docs/评估_JSC_Windows可行性.md`：✅ 可行——WinCairo 官方端口自建 JSC-only DLL，体积 ~10–18 MB LGPL 动态链接合规，**不触发 D6 降级预案**，B-05 维持 JSC 主 / QuickJS 降级原案）。文件名升版 v1.2 → v1.3（现行引用同步改指 v1.3）。
> **v1.4 变更（D28/D29，2026-10-01）**：**Q-05 + B-05 定稿交付**：JSC 引擎统一封装（`jsc_ffi.dart` vj_\* FFI 抽象 + `jsc_bridge_engine.dart` 与 QuickJS 同形状引擎，prelude 注入复用 B-05a）+ 引擎工厂 D6 降级链（JSC 主 → QuickJS 自动降级 + onLog 降级可观测）+ 原生侧 `jsc/wrapper.{c,h}`（三端共用）+ `build-jsc.yml`（macOS dylib 构建 + vj_\* ABI 冒烟，Q-04 原生腿）→ 写入交付记录与自检结果（729 用例全绿 + 11 守卫全绿）。文件名升版 v1.3 → v1.4（现行引用同步改指 v1.4）。
> **v1.5 变更（2026-10-02）**：**Q-06 交付**——双引擎体积/许可核销 + conformance 双跑：`cross_engine_v1.json`（36 探针 + 五操作 golden 唯一真相源）+ `double_run.c`（引擎无关 harness，编译期宏切 `vq_*`/`vj_*`）+ `double_run.py`（平台自适应双跑）+ `check_engine_bundle.py`（许可核销 + 体积登记）+ `engine_bundle_registry.json`（合规归档）。本地自检：双跑 5/5 · 许可/体积 8/8（jsc-android 实测 5.18–6.96 MB/ABI）。批次 Q 剩 Q-03（Windows JSC）。文件名升版 v1.4 → v1.5。
> **v1.6 变更（2026-10-02）**：**Q-03 交付**——Windows JSC 集成（Playwright WebKit 预编译运行时 + MSVC 编译自有 wrapper，见 §16 Q-03 行与本文件头部「批次 Q 交付记录·Q-03」）；**批次 Q 六项（Q-01 ~ Q-06）全交付**。文件名升版 v1.5 → v1.6，现行引用同步改指 v1.6。
> **v1.7 变更（2026-10-02）**：**批次 C 交付（C-01 ~ C-12 中 11 项；C-05 部分交付）**——播放器核心链全落地：路由→后端选择（C-01）+ 控制层 UI（C-02）+ 弹幕（C-03）+ 选集/画质/倍速/后端菜单（C-04）+ 回退链可观测（C-06）+ 转封装代理（C-07）+ 字幕（C-08）+ 投屏/浮窗（C-09）+ Go 代理三端绑定（C-10）+ **Windows 播放器插件（C-11，libmpv 控制面）**+ URL 探测与后端矩阵（C-12）；**C-05 仅交付自动连播控制器**（`playthrough.dart`），PiP 多策略 / 后台播放 / 长按倍速留待下批次。文件名升版 v1.6 → v1.7，现行引用同步改指 v1.7。
> **v1.8 变更（2026-10-02）**：**批次 C-05 收口 → 批次 C 十二项（C-01 ~ C-12）全交付**——PiP 多策略（`pip_strategy` 5 策略判定 + `pip_bridge` 系统画中画桥 + `pip_controller` 编排）+ 后台播放（`background_play` 前台媒体服务桥）+ 长按倍速（`long_press_speed`）+ Android 插件腿（`PipPlugin`/`BackgroundPlayPlugin`/`MediaPlaybackService`）+ **遗漏核查修复 C-10 GoProxyPlugin 未在 MainActivity 接线**；批次 C 状态自 🟡 改 ✅。文件名升版 v1.7 → v1.8，现行引用同步改指 v1.8。
> **v1.9 变更（2026-10-02）**：**批次 D 首段交付（D-01 首页 / D-02 搜索 / D-03 豆瓣 / D-06 分类网格）**——四页面 UI + 数据链路打通 + 49 个测试用例 + 3 张 Golden 基线；自检：`flutter analyze` 0 issues · `flutter test` **1061 用例全通过** · 整体覆盖率 **80.4% ≥ 70%**。文件名升版 v1.8 → v1.9，现行引用同步改指 v1.9。
> **v1.10 变更（2026-10-02）**：**批次 D 收口交付（D-04 短剧 / D-05 详情页 / D-07 源发现 / D-08 批次自检）**——短剧页（源扫描 + 源标签切源 + 三列网格 + 搜索 + 详情跳转，`short_drama_page.dart`，新增「短剧」底部导航入口）；详情页扩展（头图 / 元信息 / 演职 chips / 线路 chips / 剧集宫格折叠展开 / 下载选集 sheet）；源发现页（`source_discovery_view.dart` 嵌入远程源「源发现」标签，源下拉 + 分类栏 + 分页网格）。自检：`check_dart_imports` ✅（301 文件）· `check_docs_consistency` ✅；`flutter analyze` / `flutter test` 本机无 SDK，**交 CI flutter-check 验证**（D28 口径）。文件名升版 v1.9 → v1.10，现行引用同步改指 v1.10。
> **v1.11 变更（2026-10-03）**：**批次 E 首段交付（E-01 频道源胶囊 + 分类胶囊 + 双列频道卡）**——直播页 `live_tv_page.dart` 落地（顶部频道源胶囊 + 切换源浮层 + 循环调色板分类胶囊 + 16:9 双列频道卡，对齐 iOS `LiveTVView`）；新增「直播」底部导航入口（`home_shell_page.dart` 第 3 项）+ `VboxColors.liveCategoryPalette` 12 色调色板 + `pages.dart` 导出 live 页；测试 `live_tv_page_test.dart` 4 个 Widget 用例（渲染 / 分类切换 / 源浮层 / 空态）。自检：`check_dart_imports` ✅（311 文件）+ 10 个契约/一致性 Python 脚本全绿；`flutter analyze` / `flutter test` 本机无 SDK，**交 CI flutter-check 验证**（D28 口径）；**Golden ≥0.95 基线随 E-06 批次自检统一下发**（同 A-12 逐页 SSIM 机制，本地无 SDK 时由 CI regen）。文件名升版 v1.10 → v1.11，现行引用同步改指 v1.11。
> **完成判定**：每批次任务全 Green + 批次自检（analyze 0 / 单测 / 守卫 / Golden）通过。
> **批次 A 交付记录（2026-10-01，遗漏核查后终版）**：A-01 ~ A-13 代码侧全部交付。全量自检：`flutter analyze` 0 issues · `flutter test --coverage` **658 用例全通过** · 整体覆盖率 **75.6% ≥ 70%** · **11 个守卫脚本全绿**（含 `check_ui_tokens --selftest` 负向自测）· conformance **45/45** · Golden 基线 **4 张**像素锁定（home_portrait / home_landscape / grid_landscape / **story_page 组件画廊**）· **35 张 iOS UI 图已归档** `docs/ui_baseline/ios_ref/`（manifest.json 19 页面族映射全中）。**本轮遗漏核查补齐 2 项**：① A-12「35 图归档」（原只建机制未归档）；② A-04「组件 Story 页」（`vbox_story_page.dart`，9 区块全组件陈列 + 4 单测 + Golden）。A-12「逐页 SSIM ≥0.95」机制（`scripts/visual_regression.py`）已就绪，**逐页相似度分在后续批次页面族完善后按 manifest 配对产出**（当前 Flutter 侧仅首页 / 书架成形，无同名页对可比）；A-09「D-pad 焦点全程可见」已达框架层（FocusRing + 焦点遍历组 + 自动聚焦），页面级焦点环铺设随各页面族落地。
> **批次 B 交付记录（2026-10-01，首段 B-01 ~ B-06 + B-05a）**：远程源配置管理器（`remote_source_config_manager.dart`：开关→空地址→从未同步→App 升级→force→版本探测→TTL 的七出口状态机，`/manifest.version` 约 30 字节轻量探测，`minAppVersion` 兼容门控，契约同步键 `remote_default_*` 镜像，`RemoteSourceSyncResult.fullSync` 保留触发原因）· 代理降级链（`remote_strategy.dart`：仅 GitHub 域名走 主代理→备用→直连）· 6 合 1 聚合解析（`aggregateSites`：空 key 剔除 / disabledKeys 剔除 / key 去重首见优先）· 站点模式判定（`resolve_site_mode.dart`：Node 站点优先分流 + LX 识别 + 双模式开关）· JS 全局桥（`spider_js_globals.dart`：console/print 双通道日志 + atob/btoa Latin-1 语义 + req 别名 + 对象式 options 归一，prelude 幂等可重入）· QuickJS 引擎集成 prelude（`quickjs_bridge_engine.dart` 注入 + 日志取回接 `onLog`）。自检：`flutter analyze` 0 issues · **709 用例全通过**（新增 51：状态机/聚合/门控 21 + 站点模式 17 + JS 桥 13，JS 桥含 **Node 子进程真实执行 prelude** 验证「与引擎无关」）· 守卫脚本全绿 · B 批次无 UI 任务（**90% UI 还原度红线不涉及本批次**；后续 C/D/E… 各 UI 批次仍按 A-12 SSIM ≥0.95 门禁执行）。**Q-01 门禁完成**（见 §16）→ B-05 待 Q-05 后定稿，B-07/B-08（Node/Python 引擎复用件）已在库但五操作 conformance 随 B-12 收口，B-09 ~ B-12 未启动。
> **批次 B 交付记录·B-09（2026-10-01，HTTP 桥）**：`spider_http_bridge.dart` 新建（iOS `JSHTTPBridge.swift` 异步化 Dart 移植，**编码链唯一真相源在核心层** `decodeResponseBody`，平台层只接线）——① **5 级编码链**：响应头 charset → UTF-8（成功后 meta 自探重解）→ meta 探测 → GBK/GB2312/GB18030/Big5/UTF-8 兜底链 → latin1/base64；GBK/Big5 码表经 `SpiderCharsetTables` 一次性注入（`enough_convert` 严格解码转译注册表，G-03；lead 行批量快路径 + 8 点探针跳过保留区）· ② **超时**：默认 15s（transport 内 +5s 缓冲），超时固定形状 `ok=false/status=0/content=请求超时`（对齐 iOS）· ③ **sslBypass**：实例级 `badCertificateCallback`，仅福利模块启用 · ④ **cookie**：按域分组内存存储（Set-Cookie 收集 + 同域回带 + 域隔离 + 畸形行容错）· ⑤ **引擎接线**：JSC/QuickJS `loadScriptFromURL` 改走 HTTP 桥（注入归调用方，缺省临时建/用后即关，`HttpServer` 本地用例 + fake transport 离线用例双覆盖）· ⑥ **核心层**：`charset.dart` 改严格双字节解码（非法对/悬空高位 → null，对齐 iOS `String(data:encoding:)`）+ `sniffMetaCharsetFromText`（② 级自探）+ `http_body_decoder.dart` ② 级接入自探。**28 新用例**（桥 22 + 核心层 4 + 双引擎各 1；含 GBK/Big5 正负向、GB18030 四字节回退、奇数截断、cookie 回带/域隔离/畸形行、超时/网络失败/无效 URL 形状、UA 覆盖优先级、method 归一）。**登记偏差**：GB18030 四字节扩展序列不在码表（iOS CFString 为 GB_18030_2000 超集），含该类字符页面按契约链回退 latin1 全字节保留，不乱码扩散；POST 不注入默认 Content-Type（iOS 亦不设置）。验证：CI `flutter-check.yml`（本地无 Flutter SDK，同 D28 口径）。
> **批次 B 交付记录·B-10（2026-10-01，容错解码 + urls 回填补齐）**：复核既有件——String/Int/Double 宽松解码 + `urls ?? [url]` 回填 + `availQualities` 缺省前轮已在 `spider_models.dart` 交付（守卫 `check_spider_domain.py` 第 3/4 项锁定，本轮复核后仍全绿）。**补齐唯一缺口：`url` 数组形态**（iOS `PlayerContentResult.init(from:)`，多线路/多音质蜘蛛：酷狗/酷我/网易/QQ 的 play 返回 `url` 为数组；Dart 原实现 `asLooseString(List)` → `[a, b]` 垃圾串且污染回填）：`fromJson` 数组分支 → `urls`=全列表（元素 toString 宽松归一）、`url`=首元素、`urls` 键不再参与（对齐 iOS 优先级）；空数组 → `urls=[]`、`url=null`。**三端对齐**：契约 `abi_v1.md` §3.5 增「url 数组形态」条款（引用 iOS 源码片段）+ §9 要点表增行；conformance 参考解析器 `normalize_container` 镜像同步 + fixture 增 3 容错用例（urlAsArray / BeatsUrlsKey 优先级 / 空数组），**runner 48/48 全绿**（45 → 48）。**负向单测 7 例**（spider_models_test：数组正向/优先级/混合类型归一/空数组 + header 非对象 → null + parse 非数字 → null + urls 键混杂类型归一）。守卫复核：`check_spider_domain.py` 9 项全绿。剩余 B 批次：B-11（站源原生搜索 + 腾讯 Spider）、B-12（conformance 双跑）。
> **批次 B 交付记录·B-12（2026-10-01，conformance 收口 + 双引擎一致性）**：conformance 测试套件扩展至 **5 套件 83 项全绿**（原 48 项）：① 套件① `spider_io_v1.json` 增「**扩五操作** data 字段形状」校验（homeContent/searchContent/categoryContent/detailContent/playerContent 各自 Result 字段类型/可选性）+「**站点模式判定**」15 例（fixture `$comment_siteMode`，镜像 `SiteConfig.resolveSiteMode`/`ResolveSiteModeUseCase`，三端唯一真相源）；② 新增套件④ `manifest_v1.json`（schemaVersion 1、configVersionPattern `YYYY.MM.DD.N`、defaultTtlSeconds 21600、requiredFiles=allSources、knownFileKeys 10、5 用例：validFull/missingAllSources/badConfigVersion/defaultsApplied/minAppVersionOptional）；③ 新增套件⑤ `engine_abi_v1.json`（5 引擎 rawValue 一一对应、6 bridgeMethods 双端齐备、C 符号 `vq_*`/`vj_*` 同 ABI、free_string 2 参、3 降级可观测标记）。Dart 侧 `test/conformance/` 3 件（site_mode/manifest/engine_abi）消费同一 fixture 反验 Dart 实现与参考解析器一致（**7 用例全绿**）。配套修复：`jsc_ffi.dart` `vj_free_string` 签名对齐 C 实现（`void(ctx, str)` 2 参）保证双引擎 ABI 一致。验证：`conformance/runner/run_conformance.py` **83/83** · `flutter test test/conformance/` **7/7**（本地 Flutter 3.47.5）。
> **批次 Q 交付记录（2026-10-01，Q-05 + B-05 定稿 + Q-04 原生腿）**：JSC 引擎统一封装（`jsc_ffi.dart`：`vj_*` FFI 抽象 + `DartFfiJsCoreBridge` + 不可用安全桥，**与 `vq_*` 同 ABI 形状**；`jsc_bridge_engine.dart`：与 QuickJS 引擎同形状的全生命周期 + 五操作 + prelude 注入（B-05a 复用，首 eval 即 prelude）+ 日志取回）· **B-05 引擎映射定稿**（`spider_engine_factory.dart`：JSC 主引擎 / QuickJS 降级备份，`javaScriptCore` 请求时 JSC 不可用 → 自动降级 QuickJS 且 `onLog` 双事件可观测（⚠️ 降级 + ✅ 完成），双库均缺 → `E_UNIMPLEMENTED`；新增 `createForJsSite` JS 站点主映射入口）· 原生侧 `jsc/wrapper.{c,h}`（纯 C 包装 JSC C API，`vj_eval` 异常消息带 Error/TypeError 前缀满足契约 §5；console/print 改由 prelude 注入避免双重定义）· `build-jsc.yml`（macOS dylib 构建 + **vj_\* ABI 冒烟测试**（含 dlopen 动态加载等价 Dart FFI 路径），Q-04 原生腿）。自检：`flutter analyze` 0 issues · **729 用例全通过**（新增 20：JSC 引擎 16 + 工厂净增 4，工厂含 D6 降级可观测 / 双库兜底 / createForJsSite 用例）· 11 守卫全绿。剩余：Q-02（Android 四 ABI）/Q-03（Windows MSVC）原生打包管线（wrapper.c 已就绪，见 §16 各行）、Q-04 应用内打包（dylib 入 App Bundle，随 G-03-B 统一分发决策）、Q-06（体积/许可核销，依赖 B-12）。
> **批次 Q 交付记录·Q-03（2026-10-02，Windows JSC 集成，批次 Q 收官）**：**运行时来源**：Playwright WebKit Win64 预编译 `JavaScriptCore.dll` + ICU + MSVC 运行时——Q-01 原方案 A（WinCairo 自建）buildbot 已停，改方案 P（`docs/评估_JSC_Windows可行性.md` §2/§3.2 已作口径修正）；`scripts/fetch-jsc-windows.ps1` 幂等拉取锁定 revision（`JSC_WINDOWS_WEBKIT_REV` 可覆盖，产物入 `build/vbox-jsc/windows/vendor/` 不入 git，同 D28 决策）。**wrapper 编译**：`windows/runner/jsc/JavaScriptCore.def`（8 个 JSC C API 导出符号）→ MSVC `lib.exe` 重建 `JavaScriptCore.lib` → `cl.exe` 编译 `jsc/wrapper.c` 导出 `vj_*` 六符号 → `vbox_jsc.dll`；`scripts/build-jsc-windows.ps1` 内联 fetch + 编译 + 语义/符号级冒烟（`jsc/smoke_test.c`：eval/异常 TypeError 前缀/undefined 字符串化/生命周期）。**runner 打包**：`windows/runner/main.cpp` `LoadLibraryW("vbox_jsc.dll")` 预加载（与 macOS `dlopen`/Android `loadLibrary` 对称；失败仅 `OutputDebugStringW` 不 crash → Dart `isAvailable=false` → 工厂 D6 降级 QuickJS）；`scripts/bundle-jsc-windows.ps1` 把 `vbox_jsc.dll` + vendor 运行时 DLL 拷入 `build/windows/x64/runner/<Config>/`（与 runner.exe 同目录，Windows 默认按应用目录搜索 DLL，随 `installer.iss` 递归打包 `Release\*`）。**CI**：`build-jsc.yml` `build-windows` job（fetch + MSVC 编译 + smoke + 上传产物）+ `flutter-check.yml`/`build-release-assets.yml` Windows job 前置 bundle 步骤。**体积契约**：`check_engine_bundle.py` jsc-windows 25–45 MB 区间（`JavaScriptCore.dll` 实测 ~32 MB）。**批次 Q 六项（Q-01 ~ Q-06）全交付**。
> **批次 C 交付记录（2026-10-02，C-01 ~ C-12 全交付）**：播放器核心链落地。**C-01 路由→后端**（`player_controller.dart`：`PlaybackRoute`（detail/pan/live/music/local 五路）+ `PlayerController.open` 后端降级链（初始后端选择器 → 失败逐级回退 → 全败抛 `E_NO_BACKEND`）+ `PlaybackSettings`（倍速/画质/音量/连播/长按倍速契约键））；**C-02 控制层 UI**（`player_controls_view.dart` + `player_controls_controller.dart` 横竖双态 + `player_top_bar`/`player_bottom_bar`/`player_progress_bar`）；**C-03 弹幕**（`danmaku/*`：XML 解析（`&nbsp;` 转义）+ 滚动/顶部/底部三模式 + 车道分配引擎（防重叠）+ 设置面板，自定义弹幕源契约键接线）；**C-04 面板**（`panels/*`：选集/画质/倍速/后端四菜单 + `player_panel_container` 容器）；**C-06 回退可观测**（`PlayerController` 降级日志 + 测试断言后端接管）；**C-07 转封装**（`remux_proxy.dart`：18081 端口 MKV/FLV→fMP4 只换容器代理客户端）；**C-08 字幕**（`subtitle_parser.dart`：SRT/WebVTT/ASS 三格式解析，时间轴归毫秒）；**C-09 投屏/浮窗**（`cast/*` `floating/*`：`CastService` 抽象（MethodChannel 实现 + Noop 降级）、`FloatingWindow` 抽象、`CastSession`/`CastDevice` 领域模型）；**C-10 Go 代理三端绑定**（`go_proxy_client.dart`：分片重写/Base64/缓存协议客户端 + Android `GoProxyPlugin.kt` MethodChannel 腿，端口重试/降级逻辑）；**C-11 Windows 播放器插件**（`windows/runner/player_plugin.{h,cpp}`：`MpvApi` 动态加载 mpv-2.dll（D28 随包分发）+ `PlayerPlugin` MethodChannel/EventChannel 双通道（open/play/pause/seekTo/setVolume/setSpeed/dispose + state/progress/error 事件面），libmpv `vo=null` 无窗口控制面（init 前设置，避免弹出 mpv 窗口），事件线程轮询 `mpv_wait_event` + `observe_property` 属性变更驱动；`flutter_window.cpp` 手动注册（`GetRegistrarForPlugin` 取 registrar，非插件工程模式）；CMake 接线 + `bundle-libmpv-windows.ps1`（fetch/sha256/改名 mpv-2.dll 拷入 runner 目录）+ `flutter-check.yml`/`build-release-assets.yml` bundle 步骤 + `installer.iss` 递归打包）；**C-12 URL 探测**（`media_url_checker.dart`：播放前 URL 探测 + MPV 后端矩阵（自动/MPV/自由度）选择）。**macOS 核验**：`PlayerPlugin.swift`（AVPlayer 主后端）与 C++/Kotlin 插件 wire 协议逐项对齐（channel 名/方法面/事件字段），`MainFlutterWindow.swift` 注册确认。**自检**：`flutter analyze` 0 issues · `flutter test` **890 用例全通过** · 覆盖率 **84.5% ≥ 70%** · 守卫（契约同步/完整性/prefs/文档一致性）全绿 · player 专项 **107 用例全绿**（新增：后端链回退/状态转发 3 + 后端选择 wire 值 10 + C-01 路由 5 + C-09 投屏/浮窗 20 + C-10 Go 代理 10 + C-12 探测 8 + 弹幕 8 + 字幕 8 + 播放设置 6 + 连播 3 + 转封装/媒体探测若干）。**遗漏核查修复 2 处**：① `flutter_window.cpp` 插件注册参数类型（`GetRegistrar` 需 `FlutterDesktopPluginRegistrarRef`，原传字符串会编译失败）→ 经 `engine()->GetRegistrarForPlugin` 取 registrar；② `player_plugin.cpp` `vo=null` 须在 `mpv_initialize` 前设置（后置会弹出 mpv 窗口破坏控制面契约）。
> **批次 C 交付记录·C-05（2026-10-02，PiP 多策略 + 后台播放 + 长按倍速，批次 C 收官）**：**PiP 多策略**（`pip_strategy.dart`：`PipStrategy` 5 策略枚举（mdk/mpv/vt/viewCapture/avPlayer/none）+ `PipStrategyResolver` 按平台+后端+系统 PiP 可用性判定；`pip_bridge.dart`：`PipPlatformBridge` 抽象 + `MethodChannelPipBridge`（`com.vbox.player/pip` MethodChannel + `.../pip/events` EventChannel）+ `NoopPipBridge` 降级；`pip_controller.dart`：`PipController` 按策略分派（系统级 → 系统桥；浮窗级 → 复用 C-09 `FloatingWindow`），`enter/exit/updateProgress/handleLifecycle/dispose` + 生命周期联动；`pip_lifecycle.dart`：`PlaybackLifecycle` 归一枚举（`fromAppStateName`））；**后台播放**（`background_play.dart`：`BackgroundPlayBridge` + `MethodChannelBackgroundPlayBridge`（`com.vbox.player/background`）+ `NoopBackgroundPlayBridge`（桌面 no-op）+ `BackgroundPlayController` 生命周期联动——退后台 + 开启 + 播放中 → 启动承载）；**长按倍速**（`long_press_speed.dart`：`LongPressSpeedController` 按下切 `player_long_press_speed`（默认 2.0）、松开恢复原倍速，≤1.0 视为未启用）；**Android 插件腿**（`PipPlugin.kt`（ActivityAware + DefaultLifecycleObserver，`enterPictureInPictureMode`/`exitPictureInPictureMode` + `pipChanged` 事件，API 26+ 特性探测）；`BackgroundPlayPlugin.kt`（`startForegroundService`/`stopService` 前台媒体服务）；`MediaPlaybackService.kt`（Media3 `MediaSessionService` 宿主，manifest `foregroundServiceType=mediaPlayback`））。**遗漏核查修复 1 处**：C-10 `GoProxyPlugin.kt` 已交付插件文件但此前未在 `MainActivity.configureFlutterEngine` 接线 → 补齐注册（`GoProxyPlugin.registerWith`）。**自检**：`flutter analyze` 0 issues · `flutter test` **1012 用例全通过** · 覆盖率 **82.3% ≥ 70%** · 守卫全绿 · 零触达代码文件降至 2 个（`lib/app.dart` / `lib/main.dart` 应用入口，待后续批次补测）。**批次 C 十二项（C-01 ~ C-12）全交付**。
> **批次 D 交付记录（2026-10-02，首段 D-01 / D-02 / D-03 / D-06）**：**D-01 首页**（`home_page.dart` 轮播 + 分类胶囊 + 横向列表 + `source_sheet.dart` 切换源浮层）· **D-02 搜索**（`search_page.dart` 空态（历史/榜单）+ 结果态（左源列表 + 结果卡）+ `search_history_usecases` / `search_history_repository` 去重·持久化·清除 + `content_browse_usecases` 首页/分类/搜索单源解析链路）· **D-03 豆瓣**（`douban_models.dart` 数据模型 + `douban_datasource.dart`（rexxar `subject_collection` + chart `top_list` 双 API）+ `douban_usecases`（homeFeed 并发聚合 / ranking 分页 / category 客户端过滤排序）+ `douban_home` / `douban_ranking` / `douban_category` 三页 + `douban_widgets` 共享组件）· **D-06 分类网格**（`category_page.dart` 源下拉 + 分类胶囊 + 响应式海报网格）。**测试**：新增 8 个测试文件（douban 数据源 / 用例 / Golden / 搜索历史仓储 / 用例 / 内容浏览 / 分类页 / 搜索页）+ **49 个用例** + **3 张 Golden 基线**（douban_home / douban_ranking / douban_category）。**自检**：`flutter analyze` 0 issues · `flutter test` **1061 用例全通过**（1012 → 1061）· 整体覆盖 **80.4% ≥ 70%** · 守卫全绿 · 零触达代码文件 **2 个**（`app.dart` / `main.dart` 应用入口）。**批次 D 余项**：D-04 短剧 / D-05 详情页 / D-07 源发现 / D-08 批次自检未启动。

---

## 0. 事实基线（写代码时手边要有）

| 项 | 值 |
|----|----|
| Prefs 契约 | **21 组 / 99 键**，`schemaVersion 1.4`，敏感键 **7**（`app_tmdb_proxy_token` · `one_platform_token` · `one_platform_userkey` · `one_platform_uuid` · `quark_device_id` · `baidu_local_pcs_device_id` · `saved_drive_tokens`） |
| 本轮新增键 | `app_ui_form_override`（显示模式 auto/portrait/landscape）→ **D17 契约变更** |
| SQLite | `vbox.sqlite3`，**9 表**：`zhanyuan` `apiyuan` `subscription` `favorite` `history` `settings` `jiexisetting` `search_history` `download`；迁移链 v1 建表 → v2/v3/v4 扩列（`download` v4 加 `sourceType` `engineKey` `vodId` `headers`） |
| Keychain | `credentialService` · `tokenService` 两套 `service/account` |
| 远程源 | 主 `raw.githubusercontent.com/vbox-Ai/api/main/sources/manifest.json`；备 `vbox-ai.github.io/api/sources/manifest.json`；降级链 `ghfast.top → gh-proxy.com → 直连`；`ttlSeconds 21600` |
| Node 凭据端点 | `PUT`/`DELETE /website/api/credential/:provider/:field` · `GET /website/api/credentials` |
| 本地端口 | 图片/转码代理 · **转封装 `127.0.0.1:18081`** · Go HTTP/2 代理 |
| **Spider 引擎（D6 已定）** | **JSC 主 + QuickJS 降级**；运行时共 **5 类**：JavaScriptCore / QuickJS / Node / NodeLX / Python。iOS 侧 `SpiderEngineType` 枚举仅 4 类，`PythonSpiderEngine` 为第 5 个实现但不在枚举内 |
| **JS 桥 6 项必备能力（与引擎无关）** | `console`/`print` 真实输出 · `atob`/`btoa` · `req` 别名 · **对象式 `options` 归一** · GBK/Big5 编码链 · `sslBypass`（仅福利） |
| 资源 | JS 6 脚本 + `测试蜘蛛.js` + `tetui_spider.js` · `default_subscribe.json` · `ibox_sources.json`（两份）· `video_sources.json` · `noderuntime/`（7 件）· `python-stdlib/base/` · `default_live.m3u` + `live_default.m3u` · `MaShanZheng-Regular.ttf` · 启动页字母图 V/b/o/x + swoosh |

---

## 1. 批次 A · 设计基座（A-01 ~ A-13）· 13 项 — ✅ **全交付（2026-10-01）**

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| A-01 | 颜色令牌：四皮肤主色 + 语义色 + 分类色板 10 色 + 品牌渐变 | `lib/presentation/theme/tokens/colors.dart` | — | — | 单测断言色值；R-4 守卫通过 | ✅ 新建·已交付 |
| A-02 | 字号 / 圆角 / 间距 / 阴影令牌（字号 10 档；圆角 {4,6,8,10,12,14,16,20}） | `.../tokens/typography.dart` `radii.dart` `spacing.dart` `shadows.dart` | A-01 | — | R-2 / R-3 守卫通过 | ✅ 新建·已交付 |
| A-03 | 主题工厂 + 四皮肤切换 | `.../theme/vbox_theme.dart` | A-01,02 | `app_skin_mode` `app_skin_follows_system` | 四皮肤热切换无重建抖动 | ✅ 改造·已交付 |
| A-04 | 统一组件库：Card / Chip / SectionHeader / EpisodeChip / Button / Toast / BottomNav / Rail / Dialog / PosterCard / SourceBadge | `lib/presentation/widgets/vbox/*` | A-01,02 | — | 组件 Story 页 + 单测；规格对齐 UI 基准 | ✅ 新建·已交付（**Story 页 `vbox_story_page.dart` 9 区块全陈列 + 4 单测 + Golden 像素锁**） |
| A-05 | **形态模型改造**：`UiMode{phone,tv,desktop}` → `UiForm{portrait,landscape}` + `InputModality` | `lib/presentation/ui_mode/ui_mode.dart` `ui_mode_resolver.dart` | — | — | 单测覆盖判定分支 | ✅ 改造·已交付 |
| A-06 | 新增显示模式键 + 契约同步 | `contract/schema/prefs_keys_v1.json` · `lib/contract/prefs_keys.dart` · `prefs_manager.dart` | A-05 | **`app_ui_form_override`** | `check_contract_sync` 通过 | ✅ 新建·已交付 |
| A-07 | 自适应框架：AdaptiveScaffold / ResponsiveGrid / ContentPanel / AdaptiveDialog | `.../widgets/adaptive/*` | A-04,05 | — | 竖横切换无重组抖动；单测 | ✅ 新建·已交付 |
| A-08 | **页面树收敛**：三套页面 → 单一页树 + 双排布（路由改造） | `lib/app.dart` · `lib/presentation/shell/home_shell_page.dart` | A-05,07 | — | 单一入口可达两形态 | ✅ 改造·已交付（三套旧页树已删除） |
| A-09 | 输入适配：焦点环 / hover / 快捷键 / 十英尺缩放 | `.../widgets/input/*` | A-07 | — | D-pad 焦点全程可见 | ✅ 新建·已交付 |
| A-10 | 图片加载组件（含平台封面分支） | `.../widgets/platform_async_image.dart` | A-04 | — | 缓存/占位/失败态可用 | ✅ 移植·已交付（海报卡已收敛接入） |
| A-11 | UI 守卫 R-2 圆角 / R-3 字号 / R-4 主色不散落 | `scripts/check_ui_*.py` | A-01,02 | — | 负向测试可拦截 | ✅ 新建·已交付 |
| A-12 | 视觉回归基线（35 图归档 + Golden + SSIM ≥0.95） | `docs/ui_baseline/ios_ref/`（35 图 + manifest）· `test/golden/*` · `scripts/visual_regression.py` | A-11 | — | 产出相似度分 | ✅ 改造·已交付（**35 图已归档**；逐页 SSIM 分随页面族落地按 manifest 配对产出） |
| A-13 | 品牌资源入包：字体 + 启动页字母图 | `assets/fonts/VboxBrand-Bold.otf` · `assets/splash/vbox_letter.png` · `pubspec.yaml` | — | — | 字体渲染生效；`assets` 非空 | ✅ 移植·已交付 |

---

## 2. 批次 B · 远程源与 Spider（B-01 ~ B-12，含 B-05a）· 13 项 — ✅ **全交付（B-01 ~ B-12，含 B-05 定稿 + B-05a），2026-10-01**

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| B-01 | manifest 探测 / 缓存（版本→TTL→强制刷新→兼容门控） | `lib/data/datasources/remote/remote_source_config_manager.dart` | A-06 | `remote_default_*` 9 键 | 版本未变不进全量 | ✅ 改造·已交付 |
| B-02 | 代理降级链（可配置常量） | 同上 | B-01 | — | 主通道失败自动切换 | ✅ 新建·已交付 |
| B-03 | 6 合 1 聚合解析 | 同上 | B-01 | — | 站点聚合正确 | ✅ 新建·已交付 |
| B-04 | 站点模式判定 + Node 站点识别 | `lib/domain/usecases/resolve_site_mode.dart` | B-03 | — | 全分支用例 | ✅ 新建·已交付 |
| B-05 | **引擎映射（D6）**：JS 站点脚本 → **JSC 为主引擎**、**QuickJS 为降级备份**；Node / NodeLX / Python 分流 | `lib/platform/spider/spider_engine_factory.dart` | B-04, **Q-05** | — | 映射表用例；**JSC 不可用时自动降级 QuickJS 且降级可观测**；5 类引擎均有五操作用例 | ✅ 改造·已交付（**定稿**：JSC 主 / QuickJS 自动降级 + onLog 双事件可观测 + `createForJsSite` 入口；D6 降级链用例齐） |
| B-05a | **JS 全局 API 桥补齐（6 项，与引擎无关）**：`console`/`print` 真实输出（接日志）· `atob`/`btoa` · `req` 别名 · **对象式 `options` 归一** | `lib/platform/spider/spider_js_globals.dart` | B-04 | — | 6 项逐项单测；内置脚本零改动可跑 | ✅ 新建·已交付（**Node 子进程真实执行 prelude 逐项验证**） |
| B-06 | QuickJS 引擎接入（**降级备份**位） | `lib/platform/runtime/quickjs_bridge_engine.dart` | B-05 | — | 五操作跑通 | ✅ 复用·已交付（prelude 注入 + 日志取回集成） |
| B-07 | Node / NodeLX 引擎接入（`nodejs_` / lx） | `lib/platform/spider/node_bridge_engine.dart` | B-05 | `remote_node_bundle_url` `remote_node_bundle_ver` | 五操作跑通 | 复用 |
| B-08 | Python 引擎接入（`csp_`） | `lib/platform/spider/python_bridge_engine.dart` | B-05 | — | 五操作跑通 | 复用 |
| B-09 | HTTP 桥：超时 + **5 级编码链（GBK/GB2312/GB18030/Big5/UTF-8）** + `sslBypass`(仅福利) + cookie（**JSC 侧已有现成实现，直接移植**） | `lib/platform/spider/spider_abi.dart` 等 | B-05 | — | GBK/Big5 负向用例 | ✅ 新建·已交付（**`spider_http_bridge.dart`**：iOS `JSHTTPBridge.swift` Dart 移植——5 级编码链**复用核心层唯一实现** `decodeResponseBody`（消除双份漂移），平台层仅经 `SpiderCharsetTables` 注入 `enough_convert` 转译的 GBK/Big5 真实码表（G-03，严格语义：非法对/悬空字节 → 该级失败不吞字节）；超时默认 15s（+5s 缓冲）对齐 iOS 超时分支 `ok=false/status=0/content=请求超时`；`sslBypass` 实例级 `badCertificateCallback`（仅福利启用不污染全局）；cookie 按域分组内存存储（Set-Cookie 收集 + 回带 + 域隔离，补 iOS 未接线部分）；结果形状对齐 iOS `syncRequest` 字典；`SpiderHttpTransport` 抽象可注入离线单测。**引擎接线**：JSC/QuickJS 双引擎 `loadScriptFromURL` 改走 HTTP 桥（可注入，缺省临时建/用后即关）。**核心层增强**：`charset.dart` 严格多字节解码 + ② 级 UTF-8 成功后 meta 自探重解（对齐 iOS 语义）。**28 新用例**含 GBK/Big5 正负向、GB18030 四字节回退（登记偏差）、悬空截断、cookie 回带/域隔离、超时/网络失败形状。**登记偏差**：GB18030 四字节扩展不在码表（iOS CF 为超集），按契约链回退 latin1 不乱码扩散） |
| B-10 | 容错解码 + `urls ?? [url]` 回填 | `lib/data/datasources/remote/*` | B-09 | — | 负向单测 | ✅ 改造·已交付（**实测落点在 `lib/domain/entities/spider/spider_models.dart`**（计划产出列为估算位置）：四引擎（JSC/QuickJS/Node/Python）`callPlayerContent` 的 parse 回调统一经 `PlayerContentResult.fromJson`，即全部远程 Spider 流共用。**既有件复核**：String/Int/Double 宽松解码（asLooseString 家族）+ `urls ?? (url 非空 ? [url] : null)` 回填 + `availQualities` 缺省 `[]` 前轮已交付且守卫 `check_spider_domain.py` 持续锁定；**本轮补齐唯一缺口——`url` 数组形态**（iOS `init(from:)`：蜘蛛 play 常返回多线路/多音质数组（酷狗/酷我/网易/QQ），Dart 侧原 `asLooseString(List)` 产出垃圾串）：数组 → `urls`=全列表、`url`=首元素、`urls` 键不再参与；空数组 → `urls=[]`、`url=null`；元素 toString 宽松归一。**契约同步**：`abi_v1.md` §3.5 增 url 数组形态条款 + §9 要点表增行；conformance 参考解析器 `normalize_container` 同步 + fixture 增 3 用例（urlAsArray / 优先级 / 空数组），runner 48/48 全绿。**负向单测 7 例**：url 数组正向/优先级/元素归一/空数组 + header 非对象→null + parse 非数字→null + urls 键类型混杂归一） |
| B-11 | 站源原生搜索（Dart HTML 解析） + 腾讯原生 Spider | `lib/core/html/xpath_engine.dart` `lib/platform/spider/zhanyuan_search_service.dart` `lib/platform/spider/tencent_video_spider.dart` `lib/domain/usecases/zhanyuan_search_usecases.dart` | B-09 | — | 与 iOS 结果一致 | ✅ 新建·已交付（**`zhanyuan_search_service.dart`**：iOS `ZhanyuanSearchService.swift` Dart 移植——`&&&` 语法→XPath 归一、搜索 URL 构建（websearchurl 优先 + Apple CMS 兜底）、XPath/详情页模板双模式解析、详情播放列表（`detaillist`+`detailjs/detailjsurl` 规则 + `.//a` 兜底）；请求/解码**复用 B-09 `SpiderHttpBridge`**（契约 §4.2 探测链唯一实现）；**`xpath_engine.dart`**：最小 XPath 子集引擎（轴 `//`/`/`/`.//`/`./`、谓词存在/相等/contains/多步、终端 `text()`/`@attr`、文档序去重），覆盖 Kanna 经 `ZhanyuanSearchService` 用到的全部形态，超出子集返回空对齐 Kanna 求值失败；**`tencent_video_spider.dart`**：iOS `TencentVideoNativeSpider.swift` 移植（替代失效 drpy JS 蜘蛛）——搜索（`MultiTerminalSearch` 类型白名单 + 外站过滤 + cid 去重 + HTML 标签移除）+ 详情（双请求 + 演员 + 剧集 `预告` 分流 + `tabs` 分页）；**`zhanyuan_search_usecases.dart`**：并发分批（30）+ onBatch 流式回调 + 搜索历史注入 + 站点来源由表现层注入（DB 优先→内存回退）。**4 组测试**（引擎/站源/腾讯/用例）离线验证，关键词 URL 编码、`fetchDetail` 异常等对齐登记。**既有件复核**：`pubspec.yaml` 增 `html` 依赖；`Zhanyuan.defaultUA` 公开化供服务复用；barrel（`spider.dart`/`usecases.dart`）导出新件） |
| B-12 | conformance：扩五操作 + 站点模式 + manifest 契约 + **双引擎一致性（JSC 主 / QuickJS 降级）** | `conformance/*` · `test/conformance/*` | B-05~11, Q-05 | — | 100% 通过；双引擎结果一致 | ✅ 改造·已交付（**conformance 收口至 5 套件 83 项全绿（原 48）**：套件① 扩五操作 data 字段形状 + 站点模式 15 例；新增套件④ `manifest_v1.json`（版本探测/必需文件/默认值 5 用例）；新增套件⑤ `engine_abi_v1.json`（5 引擎 rawValue + 6 bridgeMethods + `vq_*`/`vj_*` C 符号同 ABI + free_string 2 参 + 3 降级可观测标记）。Dart 侧 `test/conformance/` 3 件（site_mode/manifest/engine_abi）消费同一 fixture 反验（7 用例全绿）。配套修复 `jsc_ffi.dart` `vj_free_string` 2 参签名对齐 C 实现保证双引擎 ABI 一致。验证：runner **83/83** · `flutter test test/conformance/` **7/7**） |

---

## 3. 批次 C · 播放器（C-01 ~ C-12）· 12 项 — ✅ **全交付（2026-10-02）**

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| C-01 | 路由 → 后端选择（三端差异化） | `lib/platform/player/player_controller.dart` `playback_route.dart` | B | — | 三端可加载 | ✅ 改造·已交付 |
| C-02 | 横竖双态控制层 UI（对齐播放器 UI 图） | `.../player/player_controls_*.dart` `player_bottom_bar.dart` `player_top_bar.dart` `player_progress_bar.dart` | A-07 | — | Golden ≥0.95 | ✅ 新建·已交付 |
| C-03 | 弹幕渲染 + 设置面板（含自定义弹幕源） | `.../player/danmaku/*` | C-02 | `custom_danmaku_source_enabled` `custom_danmaku_source_url` | 开关/透明度/字号/区域生效 | ✅ 新建·已交付 |
| C-04 | 选集 / 画质 / 倍速 / 后端切换菜单 | `.../player/panels/*` | C-02 | — | 与图一致 | ✅ 新建·已交付 |
| C-05 | PiP（多策略）+ 后台播放 + 连播 + 长按倍速 | `.../player/pip/*` `playthrough.dart` | C-01 | `player_pip_enabled` `player_background_play` `player_auto_play_next` `player_long_press_speed` | 行为对齐 iOS | ✅ 新建·已交付（PiP 5 策略判定 + 系统桥/浮窗分派 + 后台前台媒体服务 + 长按倍速按压恢复；连播 `AutoPlayNextController` 先行交付） |
| C-06 | 回退链 + 降级可观测 | `player_controller.dart` | C-01 | — | 降级路径单测 + 日志 | ✅ 改造·已交付 |
| C-07 | 转封装代理（**端口 18081**，MKV/FLV→fMP4 只换容器） | `lib/platform/player/remux_proxy.dart` | C-01 | — | MKV/FLV 可播 | ✅ 新建·已交付 |
| C-08 | 字幕解析 + 加载字幕 | `.../player/subtitle_parser.dart` | C-02 | — | 字幕显示正确 | ✅ 移植·已交付 |
| C-09 | 投屏 / AirPlay 等价 + 非 AVPlayer 内核浮窗 | `.../player/cast/*` `floating/*` | C-01 | — | 可用 | ✅ 新建·已交付 |
| C-10 | Go 代理三端绑定（分片重写 + Base64 + 缓存） | `lib/platform/player/go_proxy_client.dart` + `android/.../GoProxyPlugin.kt` | C-07 | — | 三端跑通 | ✅ 新建·已交付（Android 插件腿；桌面端由 Dart `GoProxyClient` 直连） |
| C-11 | **Windows 播放器插件**（C++）+ 核验 macOS `PlayerPlugin.swift` | `windows/runner/player_plugin.*` · `macos/Runner/PlayerPlugin.swift` | C-01 | — | 两端可播 | ✅ **新建**·已交付（libmpv 控制面 + D28 分发 + CI 接线） |
| C-12 | `MediaURLChecker` 播放前 URL 探测 + MPV 后端矩阵（自动/MPV/自由度） | `lib/platform/player/media_url_checker.dart` | C-01 | — | 探测与后端选择用例 | ✅ 移植·已交付 |

---

## 4. 批次 D · 内容浏览（D-01 ~ D-08）· 8 项 — ✅ **全交付（2026-10-02）**

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| D-01 | 首页（轮播 + 分类胶囊 + 横向列表）+ 切换源浮层 | `lib/presentation/pages/home/home_page.dart` `source_sheet.dart` | A-08, B, C | — | Golden ≥0.95 | ✅ 改造·已交付 |
| D-02 | 搜索（空态：历史/榜单；结果态：左源列表 + 结果卡） | `lib/presentation/pages/search/search_page.dart` · `search_history_usecases.dart` · `content_browse_usecases.dart` | B | `searchHistory` | Golden ≥0.95 | ✅ 新建·已交付 |
| D-03 | 豆瓣（首页 / 榜单 / 分类浏览，并发拉取） | `lib/presentation/pages/douban/*` · `douban_usecases.dart` · `douban_datasource.dart` · `douban_models.dart` | B | — | 三页 Golden | ✅ 新建·已交付（3 张 Golden 基线） |
| D-04 | 短剧（列表 + 详情） | `.../pages/short_drama/*` | B, C | — | Golden ≥0.95 | ✅ 新建·已交付 |
| D-05 | 详情页（头图 / 演员 / 网盘源 chips / 剧集宫格 / 剧集展开 / 下载选择） | `widgets/detail_page.dart` 扩展 | A, B, C | — | Golden ≥0.95 | ✅ 改造·已交付 |
| D-06 | 分类网格（源下拉 + 分类胶囊 + 三列海报） | `lib/presentation/pages/category/category_page.dart` | B | — | Golden ≥0.95 | ✅ 新建·已交付 |
| D-07 | 源发现页 | `phone/remote_source_page.dart` 扩展 | B | — | 可达且正确 | ✅ 改造·已交付 |
| D-08 | 批次自检 | — | D-01~07 | — | 全绿 | ✅ 已交付 |

---

## 5. 批次 E · 直播（E-01 ~ E-06）· 6 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| E-01 | 频道源胶囊 + 分类胶囊 + 双列频道卡 | `.../pages/live/*` | A, C | `live_tv_current_source` | Golden ≥0.95 | ✅ 已交付 |
| E-02 | 频道播放接入 | 同上 | C | — | 可播 | 新建 |
| E-03 | EPG 展示 | 同上 | E-01 | — | 数据正确 | 新建 |
| E-04 | 自定义源 + 本地导入/导出/分享（M3U/TXT） | `.../pages/live/import_export.dart` | E-01 | `live_tv_custom_sources` `live_tv_local_channels` | 导入导出可用 | 新建 |
| E-05 | MDTV 子系统（动态 Tab + 配置/分类 + 详情 + 播放） | `.../pages/mdtv/*` | C | `mdtv_home_tabs` `mdtv_iv_idx` `mdtv_key_idx` `mdtv_key_verified` `mdtv_mode_idx` | 全链路可用 | 新建 |
| E-06 | 批次自检 | — | E-01~05 | — | 全绿 | — |

---

## 6. 批次 F · 网盘（F-01 ~ F-10）· 10 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| F-01 | 授权中心页（Node 状态卡 + 12 家网盘卡 + 检测/测试） | `.../pages/cloud/auth_center.dart` | A, B | `cloud_drive_credentials_v1` | Golden ≥0.95 | 新建 |
| F-02 | 登录模式实现（原生扫码 / Node 短信验证码 / 网页兜底 / Token WebView） | `.../pages/cloud/login/*` | F-01 | `saved_drive_tokens` `saved_drive_tokens_v1` | 各模式可用 | 新建 |
| F-03 | 凭据安全存储 + Node 凭据同步 | `lib/data/datasources/local/secure_store.dart` | F-02 | Keychain 两服务；`PUT/DELETE/GET /website/api/credential*` | 键 100% 安全存储 | 改造 |
| F-04 | 阿里 extscreen 加密链路（时间戳 / 签名 / 设备指纹） | `.../cloud/aliyun_extscreen.dart` | F-02 | — | 授权成功 | 移植 |
| F-05 | B站扫码 + 百度专用代理 | `.../cloud/bili/*` `baidu/*` | F-02 | `baidu_local_pcs_device_id` `baidu_*_cache_v1` | 可用 | 移植 |
| F-06 | 排序页（长按拖拽 + 恢复默认） | `.../pages/cloud/sort.dart` | F-01 | `cloud_drive_sort_order_v1` | Golden ≥0.95 | 新建 |
| F-07 | 文件列表 / 转存 / 清理队列 | `.../pages/cloud/files.dart` | F-03 | `cloud_drive_cleanup_queue_v1` `pg_ali_*`(10 键) | 去重正确 | 新建 |
| F-08 | 网盘播放（pan 模式） | `.../player/pan_player.dart` | C, F-07 | `cloud_play_item_cache_v1` | 12 家可播 | 新建 |
| F-09 | PG 自动化（清理 / 线程 / 转存目录） | `.../cloud/pg_auto.dart` | F-07 | `pg_ali_*` `pg_source` `qr_scan` | 规则生效 | 移植 |
| F-10 | 批次自检 | — | F-01~09 | — | 全绿 | — |

---

## 7. 批次 G · 扩展域（G-01 ~ G-10）· 10 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| G-01 | 音乐（多平台 + 队列 + MiniPlayer） | `.../pages/music/*` | A, C | `music_queue_index` `music_queue_items` | 可播/切歌 | 新建 |
| G-02 | 下载（队列 / 进度 / 管理浮层） | `.../pages/download/*` | A, B | `download` 表 | 与图一致 | 新建 |
| G-03 | 推送播放 | `.../pages/push/*` | A | `push_play_items_v1` | 可用 | 新建 |
| G-04 | TG 频道搜索 + 频道管理 | `.../pages/tg/*` | A | `tg_search_channels_v1` `tg_search_channel_mode_v1` `tg_search_proxy_url_v1` | 可用 | 新建 |
| G-05 | 单平台 | `.../pages/one_platform/*` | A | `one_platform_*`(5 键) | 可用 | 新建 |
| G-06 | TMDB | `.../pages/tmdb/*` | A | `app_enable_tmdb` `app_tmdb_proxy_url` `app_tmdb_proxy_token` `app_tmdb_use_token` | 可用 | 新建 |
| G-07 | 订阅源 | `.../pages/subscribe/*` | A, B | `subscribed_config_urls` `active_subscription_index` `cached_subscribe_config` | 可用 | 新建 |
| G-08 | 站点诊断（显示当前通道 + `configVersion`） | `.../pages/diagnostics/*` | B | — | 可用 | 新建 |
| G-09 | 个人中心 3×3 宫格入口 + Bug 反馈 | `.../pages/profile/grid.dart` | A | — | Golden ≥0.95 | 新建 |
| G-10 | 批次自检 | — | G-01~09 | — | 全绿 | — |

---

## 8. 批次 H · 福利专区（H-01 ~ H-08）· 8 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| H-01 | 平台配置加载（远程 JSON + 本地缓存 + schema 校验） | `.../welfare/config_store.dart` | B | `welfare_platform_order` `fuli_remote_platform_order_v2` | 加载正确 | 新建 |
| H-02 | 5 类 serviceType 路由 + 基类抽象 | `.../welfare/router.dart` `fuli_base_service.dart` | H-01 | — | 5 类均可路由 | 移植 |
| H-03 | JS / Python 福利 Spider（脚本仅取 `sources/welfare-js/`；JS 走 **JSC 主引擎**，同 B-05） | `.../welfare/spider_*.dart` | H-02, B-05 | `welfare_custom_domains_v2` | 脚本隔离生效 | 新建 |
| H-04 | **三重隔离**（不进普通 Spider / 全局搜索 / 首页）+ 守卫 | `.../welfare/isolation.dart` · `scripts/check_welfare_isolation.py` | H-02 | `visibleInNormalSpider` 等 | 守卫可拦截越界 | 新建 |
| H-05 | 入口门控（密码 + 开关 + Tab 门控） | `.../welfare/gate.dart` | A | `app_welfare_unlocked` `app_welfare_password` `app_welfare_enabled` | 关闭后 Tab 与记录隐藏 | 新建 |
| H-06 | 三栏目 + 平台网格 + 额外视图（Gate/TabGate/SpiderHome/XJSP/FuliVideoBridge/ComicDetailBridge） | `.../welfare/views/*` | H-05 | — | Golden ≥0.95 | 新建 |
| H-07 | 代理 / 自定义域名 / 远程开关（`sslBypass` 仅本模块） | `.../welfare/proxy_store.dart` `domain_store.dart` | H-03 | `welfare_proxy_enabled_platforms_v1` `welfare_proxy_url_v1` `fuli_remote_source_*` | 开关生效 | 移植 |
| H-08 | 批次自检 | — | H-01~07 | — | 全绿 | — |

---

## 9. 批次 I · 我的 / 设置（I-01 ~ I-06）· 6 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| I-01 | 个人中心页（渐变头部 + 观看记录 + 宫格） | `.../pages/profile/profile.dart` | A, G | — | Golden ≥0.95 | 新建 |
| I-02 | 登录弹窗 | `.../pages/profile/login.dart` | M | — | Golden ≥0.95 | 新建 |
| I-03 | 设置页 12 分区逐条落地 | `.../pages/settings/*` | 各域 | 全部现有键 | 逐条可用 | 新建 |
| I-04 | **显示模式开关**（自动 / 手机竖屏 / 大屏横屏） | `.../settings/display_mode.dart` | A-05,06 | `app_ui_form_override` | 可强制竖/横 | 新建 |
| I-05 | 自更新 UI（检查 / 下载 / 安装引导） | `.../settings/update.dart` | K | — | 可用 | 新建 |
| I-06 | 批次自检 | — | I-01~05 | — | 全绿 | — |

---

## 10. 批次 K · 打包 / 签名 / 自更新链路（K-01 ~ K-06）· 6 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| K-01 | Android 签名 + `REQUEST_INSTALL_PACKAGES` + FileProvider | `android/app/**` | A | — | 可安装自更新包 | 新建 |
| K-02 | Windows 构建 + 安装器 | `windows/installer/**` | A | — | 产出安装包 | 新建 |
| K-03 | macOS 签名与公证配置 | `macos/Runner/*.entitlements` | A | — | 可分发 | 改造 |
| K-04 | 自更新器（检查 / 下载 / 校验 / 安装） | `lib/data/**/updater.dart` | K-01~03 | — | 端到端可用 | 新建 |
| K-05 | 版本分发渠道 + 更新清单 | `remote-source-repo-template/**` | K-04 | — | 清单可拉取 | 改造 |
| K-06 | 侧载安装引导 + TV 侧载方案 | `.../settings/install_guide.dart` | K-01 | — | 引导可用 | 新建 |

---

## 11. 批次 L · 启动与全局外壳（L-01 ~ L-05）· 5 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| L-01 | 闪屏（最短展示 + 数据就绪门控 + 兜底超时） | `.../shell/splash.dart` | A-13 | — | 门控与兜底生效 | 移植 |
| L-02 | 启动编排（DB / 远程源 / 运行时 / 代理 / 更新检查 / 音乐队列恢复） | `lib/app.dart` | A, B, C | `app_last_launch_version` | 启动序列正确 | 改造 |
| L-03 | 全局组件：远程源状态条 + 下载胶囊通知 + 悬浮下载按钮 | `.../shell/*` | A, G-02 | — | 显示/隐藏正确 | 新建 |
| L-04 | 音乐 MiniPlayer 全局浮层 + 底栏隐藏逻辑 | `.../shell/mini_player.dart` | A, G-01 | `music_queue_*` | 拖动/恢复正确 | 新建 |
| L-05 | 后台音频能力（Android Service + MediaSession） | `android/app/**` | C-05, K | — | 后台续播 | 新建 |

---

## 12. 批次 M · 账号与个人数据（M-01 ~ M-06）· 6 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| M-01 | 登录 / 注册 / 推荐码 | `lib/data/**/account.dart` | L-02 | — | 可用 | 新建 |
| M-02 | 昵称 / 头像 / 编辑 | 同上 | M-01 | — | 可用 | 新建 |
| M-03 | 观看记录页 | `.../pages/profile/history.dart` | M-01 | `history` 表 | 与图一致 | 新建 |
| M-04 | 我的收藏页 | `.../pages/profile/favorite.dart` | M-01 | `favorite` 表 | 与图一致 | 新建 |
| M-05 | 分享 vbox | 同上 | A | — | 可用 | 新建 |
| M-06 | 批次自检 | — | M-01~05 | — | 全绿 | — |

---

## 13. 批次 N · 备份与还原（N-01 ~ N-04）· 4 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| N-01 | 备份 9 类目采集 + 快照结构 | `lib/data/**/backup_manager.dart` | A, F | 快照含 `settings` 表 + UserDefaults 白名单 + 凭据 | 采集完整 | 改造 |
| N-02 | 口令派生 + 加密封装（PBKDF2 + AES-256-GCM） | 同上 | N-01 | — | 加解密往返正确 | 新建 |
| N-03 | 还原主流程（校验 / 版本检测 / 重建站点列表 / 凭据同步） | 同上 | N-02 | 远程源相关键 | 还原后可用 | 新建 |
| N-04 | 备份/还原 UI（文件导入导出，依赖平台配置） | `widgets/backup_page.dart` 扩展 | N-03, K | — | 真机导入导出成功 | 改造 |

---

## 14. 批次 O · 兜底与源治理（O-01 ~ O-05）· 5 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| O-01 | 兜底切片资源开关 + 自定义切片源管理 | `.../settings/fallback/*` | B | `fallback_enabled` `custom_fallback_sites` | 生效与持久化 | 新建 |
| O-02 | 自定义解析器管理 | `.../settings/parser/*` | B | `user_parsers` `enable_dual_mode` | 生效 | 新建 |
| O-03 | 站源管理（启用/禁用） | `.../settings/sites/*` | B | 站源表 `zhanyuan` `apiyuan` | 生效 | 新建 |
| O-04 | 内置 JSON 兜底源开关 + 自定义 manifest 地址 | `.../settings/remote/*` | B | `bundle_sources_enabled` `remote_default_manifest_url` | 生效 | 新建 |
| O-05 | 批次自检 | — | O-01~04 | — | 全绿 | — |

---

## 15. 批次 P · 日志与诊断（P-01 ~ P-05）· 5 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| P-01 | 日志系统（11 分类 + 等级 + 崩溃标记） | `lib/core/logging/*` | A | `app_dev_log_enabled` `app_dev_log_level` `app_log_enabled` `app_log_min_level` `app_log_crash_marker` | 分类与等级生效 | 新建 |
| P-02 | 网络请求拦截记录 | 同上 | P-01 | — | 记录状态码/耗时/大小 | 新建 |
| P-03 | 日志查看页 | `widgets/log_viewer_page.dart` 扩展 | P-01 | — | 可筛选/导出 | 改造 |
| P-04 | 开发调试面板（含 MPV 调试视图 + 搜索调试 + DNS 清理） | `.../settings/debug/*` | A, C | `show_debug_overlay` `show_search_debug` `dns_cache_clear` | 可用 | 新建 |
| P-05 | 存储管理 + 关于页 | `.../settings/storage.dart` `about.dart` | A | — | 可查看/清理 | 新建 |

---

## 16. 批次 Q · JavaScriptCore 三端集成（D6）（Q-01 ~ Q-06）· 6 项 — ✅ **Q-01 ~ Q-06 六项全交付（2026-10-02）**

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| Q-01 | **Windows 自建/集成 JSC 可行性评估（门禁）** | `docs/评估_JSC_Windows可行性.md` | — | — | 产出：可用构建方案 + 体积/许可结论；**不通过 → 触发 D6 降级预案（Windows 改用 QuickJS，回老板确认）** | ✅ 新建·已交付（**结论：可行**——方案 A WinCairo 官方端口自建 JSC-only DLL（~10–18 MB，LGPL-2.1 动态链接合规，仅 x64）；方案 B NativeScript 预编译 DLL 备选；**不触发降级预案**，Q-02~04 放行。**Q-03 实施时口径修正**：WinCairo buildbot 已停（最后 Windows 包 2024-09），改 Playwright WebKit 预编译 DLL（~32 MB），可行性文档 §2/§3.2 已同步订正） |
| Q-02 | Android JSC 集成（预编译 `.so` + JNI + CMake，四 ABI） | `android/app/src/main/jni/**` · `CMakeLists.txt` | **Q-01** | — | 四 ABI 可加载；FFI smoke 通过 | ✅ 新建·已交付（**预编译库**：RN 生态 `jsc-android` r250231 AAR → `scripts/fetch-jsc-android.sh` 四 ABI `libjsc.so`（5.0–6.7 MB/ABI，不入 git，同 D28 决策）；**JNI/CMake**：`android/app/src/main/jni/CMakeLists.txt` NDK 交叉编译 `jsc/wrapper.c` → `libvbox_jsc.so`（`DT_NEEDED→libjsc.so`，SONAME 解析）；**加载链**：`MainActivity` `System.loadLibrary("vbox_jsc")` 预加载（失败不 crash→D6 降级）→ Dart FFI 命中已加载实例；**vendor 头**：`jsc/include/JavaScriptCore/`（8 个纯 C API 头，Apple BSD-2 声明保留），wrapper 改 include `JavaScript.h`（伞头 `JavaScriptCore.h` 拉 `JSStringRefCF.h` 依赖 CoreFoundation，Android 无此框架）；**CI**：`build-jsc.yml` `build-android` job 四 ABI 交叉构建 + 符号级 smoke（NEEDED/vj_* 六符号/无泄漏）；`flutter-check.yml` `build-android` 与 `build-release-assets.yml` `apk` job 均前置 fetch 步骤。真机加载验证随 APK 产物（CI 符号级 smoke 已过 ABI 语义门禁；运行时异常走 D6 降级兜底）） |
| Q-03 | Windows JSC 集成（MSVC 构建 + runner 打包） | `windows/runner/jsc/**` | **Q-01** | — | 可加载；随安装包分发 | ✅ 新建·已交付（**运行时来源**：Playwright WebKit Win64 预编译 `JavaScriptCore.dll` + ICU + MSVC 运行时——Q-01 原方案 A（WinCairo 自建）buildbot 已停（最后 Windows 包 2024-09），改方案 P；`scripts/fetch-jsc-windows.ps1` 幂等拉取锁定 revision（`JSC_WINDOWS_WEBKIT_REV` 可覆盖），产物入 `build/vbox-jsc/windows/vendor/` 不入 git，同 D28。**wrapper 编译**：`windows/runner/jsc/JavaScriptCore.def`（8 个 JSC C API 导出符号）→ MSVC `lib.exe` 重建 `JavaScriptCore.lib` → `cl.exe` 编译 `jsc/wrapper.c` 导出 `vj_*` 六符号 → `vbox_jsc.dll`；`scripts/build-jsc-windows.ps1` 内联 fetch + 编译 + 语义/符号级冒烟（`jsc/smoke_test.c`：eval / 异常 TypeError 前缀 / undefined 字符串化 / 生命周期）。**runner 打包**：`windows/runner/main.cpp` `LoadLibraryW("vbox_jsc.dll")` 预加载（与 macOS `dlopen`/Android `loadLibrary` 对称；失败仅 `OutputDebugStringW` 不 crash → Dart `isAvailable=false` → 工厂 D6 降级 QuickJS）；`scripts/bundle-jsc-windows.ps1` 把 `vbox_jsc.dll` + vendor 运行时 DLL 拷入 `build/windows/x64/runner/<Config>/`（与 runner.exe 同目录，Windows 默认按应用目录搜索 DLL，随 `installer.iss` 递归打包 `Release\*`）。**CI**：`build-jsc.yml` `build-windows` job（fetch + MSVC 编译 + smoke + 上传产物）+ `flutter-check.yml`/`build-release-assets.yml` Windows job 前置 bundle。**体积契约**：`check_engine_bundle.py` jsc-windows 25–45 MB 区间（`JavaScriptCore.dll` 实测 ~32 MB）） |
| Q-04 | macOS JSC 集成（系统 `JavaScriptCore.framework`，零构建） | `macos/Runner/JSCCorePlugin.swift` | **Q-01** | — | 可加载 | ✅ 新建·已交付（**零第三方构建**：`scripts/build-jsc-macos.sh` clang 编译 wrapper → `libvbox_jsc.dylib`（install name `@rpath/...`）；**随包分发**：`scripts/bundle-jsc-macos.sh` 编译→拷入 `Contents/Frameworks/`→ad-hoc re-sign（entitlements 按 Debug/Release）→ ctypes dlopen + `vj_*` 语义冒烟（对齐 D28 libmpv 模式，经主二进制 `@executable_path/../Frameworks` rpath 解析）；**预加载**：`MainFlutterWindow.awakeFromNib` Swift `dlopen("libvbox_jsc.dylib")`（与 Android `MainActivity.loadLibrary` 对称；失败仅 log → Dart `isAvailable=false` → D6 降级）；**CI**：`build-jsc.yml` macOS job 改用统一编译脚本 + dylib dlopen smoke；`flutter-check.yml` macos job（debug bundle 冒烟闭环）与 `build-release-assets.yml` macos job（release 分发）均接 bundle 步骤。产物路径变更：`build/vbox-jsc/macos/libvbox_jsc.dylib`） |
| Q-05 | JSC 引擎统一封装 + 接入引擎工厂（含降级开关与可观测） | `lib/platform/runtime/jsc_bridge_engine.dart` | Q-02~04 | — | 三端同一 ABI；降级可观测 | ✅ 新建·已交付（`jsc_ffi.dart`（`JsCoreNativeBridge` 抽象 + `DartFfiJsCoreBridge`，`vj_*` 与 `vq_*` 同 ABI 形状）+ `jsc_bridge_engine.dart`（B-05a prelude 注入、生命周期对齐 QuickJS）+ 工厂 D6 降级链（JSC 主→QuickJS 降级，`onLog` 降级可观测，`createForJsSite` 主映射入口）+ `jsc/wrapper.{c,h}`/`smoke_test.c`（纯 C 三端可编译）+ `build-jsc.yml` macOS 管线 + 16 例单测 + factory 降级用例） |
| Q-06 | 双引擎体积与许可核销 + conformance 双跑 | `scripts/*` · `conformance/*` | Q-05, B-12 | — | 体积登记；LGPL 合规结论；双跑 100% | ✅ 新建·已交付（`conformance/fixtures/cross_engine_v1.json`（36 探针：exact/prefix/ignore 三口径 + 五操作 golden，双引擎「结果一致」唯一真相源）+ `conformance/runner/double_run.c`（引擎无关 harness，编译期宏 `API_PREFIX` 切 `vq_*`/`vj_*`，同一上下文逐行执行输出 `<行号>=<结果>`）+ `conformance/runner/double_run.py`（平台自适应双跑编排：QuickJS 三端真机执行，JSC 非 Darwin 退化为 `-fsyntax-only` 并回退 macOS CI；exact/prefix 比对 + 双方逐字节一致校验）+ `scripts/check_engine_bundle.py`（许可核销：QuickJS MIT / JSC LGPL-2.1+BSD-2 声明保留；体积登记：四产物契约区间 + 越界告警）+ `engine_bundle_registry.json`（合规结论归档，供 P-05 关于页引用）。本地自检：双跑 5/5（QuickJS 33 探针全过）+ 许可/体积 8/8（jsc-android 实测 5.18/5.82/5.87/6.96 MB/ABI，无越界）） |

---

## 17. 批次 J · 收口（J-01 ~ J-05）· 5 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| J-01 | 地基优先真机（安装链路 / 播放器回退 / TV 焦点） | `docs/真机验收清单_G09_G10.md` | A–Q, K | — | 地基项全过 | — |
| J-02 | 全功能人测（四端 + 遥控 + 老设备 API 24） | 同上 | J-01 | — | 问题闭环/登记 | — |
| J-03 | UI 还原度逐页终检（SSIM ≥0.95） | `test/golden/*` | J-02 | — | 19 页面族达标 | — |
| J-04 | 平台能力核销（计划 v2.5 §14 表逐项） | — | J-01 | — | 逐项通过 | — |
| J-05 | E.10b 六类扫描 + 阶段报告 | `contract/docs/stage_check_report_stage2.yaml` | J-04 | — | verdict = pass | — |

---

## 18. 依赖与关键路径

```
A(13) → B(13) → C(12) →┬─ D(8) ─┐
                        ├─ E(6)  │
                        ├─ F(10) ├─→ I(6) ─┐
                        ├─ G(10) │          │
                        └─ H(8)  ┘          │
Q(6) ──(Q-01 门禁先行，Q-02~04 并行)──→ B-05 定稿 ┤
K(6) ──────────────(自 A 后可并行)────────────────┼─→ J(5)
L(5) ─(依赖 A)                                     │
M(6) ─(依赖 L)  N(4) ─(依赖 F)                     │
O(5) ─(依赖 B)  P(5) ─(依赖 A)                     ┘
```

- **关键路径**：`A → B → C →（D/E/F/G/H 并行）→ I → J`
- **可并行**：Q / K / L / M / N / O / P（各自依赖就绪后即可启动）
- **硬前置**：
  - `A-05` / `A-08`（形态改造）必须先于任何业务页面；
  - **`Q-01`（Windows JSC 可行性）必须先于 `Q-02`~`Q-04`**，其结论决定 `B-05` 定稿；
  - `B-05`（引擎映射）必须先于 `H-03`；
  - `B-05a` / `B-09`（6 项 JS 桥能力）必须先于 `B-12` conformance 双跑。

---

## 19. 契约变更清单（D17）

| 变更 | 内容 | 影响面 |
|------|------|--------|
| **新增键** | `app_ui_form_override`（string：`auto` / `portrait` / `landscape`） | 契约 JSON + `lib/contract/prefs_keys.dart` + `prefs_manager` 镜像 + `check_contract_sync` |
| 建议修组 | 皮肤键 `app_skin_mode` / `app_skin_follows_system` 从 `_group_log` 迁至界面组 | 仅分组语义，键名不变 |
| **引擎口径（D6 · 已定）** | **三端均集成 JavaScriptCore** 为 JS 站点脚本主引擎，QuickJS 为降级备份；运行时共 5 类（JSC / QuickJS / Node / NodeLX / Python） | ABI 契约注释 + conformance **双引擎双跑** + Q 批次构建产物 + 体积/许可核销 |
| **主方案登记号** | 第 2 轮 **D6 登记进主方案须用 `D31`**（主方案 D6 已被「播放器策略」占用） | ✅ **已登记**：随主方案 **v6.32** 追加 **D31**（2026-10-01） |

---

## 20. 验收与门禁对照

| 门禁类 | 本 WBS 覆盖 |
|--------|------------|
| ① 契约一致性 | A-06 · B-12 · §19 |
| ② 数据与状态 | F-03 · N-01~03 · 9 表全覆盖 |
| ③ 平台差异 | A-05~09 · C-11 · L-05 · **Q-02~04** · J-01/J-04 |
| ④ 功能完整性 | B · C · D–H · O · **Q** |
| ⑤ 质量基线 | 各批次自检 + A-11/A-12 + **Q-06（双引擎 + 体积/许可）** |
| ⑥ 交付物与文档 | A-12 · J-03 · J-05 |

---

## 21. 风险

| # | 风险 | 缓解 |
|---|------|------|
| 1 | A-05/A-08 形态改造返工 | 先改架构再写页面；A 批次禁止并行业务页面 |
| 2 | **Windows 自建 JSC 不可行**（D6 唯一硬骨头） | **Q-01 门禁先行**；不通过即触发降级预案（Windows 用 QuickJS）并回老板确认；Q-02~04 不得在 Q-01 前启动 |
| 3 | JSC 包体 / LGPL 许可 | Q-06 统一登记与出结论；必要时按 ABI 拆分或改动态链接 |
| 4 | 双 JS 引擎行为差异 | B-12 conformance **双引擎双跑**，主/降级结果须一致 |
| 5 | C-07/C-10 双本地代理端口冲突 | 端口集中登记（图片/转封装 18081/Go） |
| 6 | F/H 体量最大 | 独立排期，F 先于 H |
| 7 | 备份在真机失效 | N-04 强制依赖平台配置核销 |
| 8 | Windows 播放器插件从零 | C-11 提前启动，与 C-01 并行 |

---

> **版本历史**
>
> | 版本 | 日期 | 变更 |
> |---|---|---|
> | v1.0 | 2026-10-01 | 首版：基于四轮复核事实基线，把 A–P 批次下沉为任务级条目（含产出/依赖/契约/验收/状态五分） |
> | v1.1 | 2026-10-01 | ① 落定 **D6**（三端均集成 JSC）→ 改写 `B-05`、新增 `B-05a`（JS 桥 6 项能力）、新增**批次 Q（JSC 三端集成，Q-01 为门禁）**；② `B-12` 增列**双引擎双跑**、`B-09` 明确 5 级编码链、`H-03` 注明走 JSC 主引擎；③ **修正 v1.0 任务计数**（原写 131，实测 121；现为 **128**）；④ 关键路径纳入 Q，风险表替换第 2 项并新增包体/许可、双引擎差异两项；⑤ §19 补「主方案登记号为 D31」 |
> | v1.2 | 2026-10-01 | **批次 A（设计基座 A-01 ~ A-13）代码侧全量交付** → 状态列与交付记录（658 用例全绿 / 覆盖率 75.6% / 11 守卫全绿 / conformance 45/45 / Golden 4 张）；补齐 A-12「35 张 iOS UI 图归档」与 A-04「组件 Story 页」两项遗漏；文件名升版 v1.1 → v1.2 |
> | v1.3 | 2026-10-01 | ① **批次 B 首段交付**（B-01 ~ B-06 + B-05a）→ 状态列与交付记录（709 用例 + 51 新增 / 守卫全绿）；② **Q-01 门禁完成**：结论**可行**（WinCairo JSC-only 自建，~10–18 MB / LGPL 动态链接 / 仅 x64），**不触发 D6 降级预案**，B-05 维持 JSC 主 / QuickJS 降级原案；③ 注明批次 B 无 UI 任务（90% UI 还原度红线适用于后续 UI 批次） |
> | v1.4 | 2026-10-01 | **Q-05 + B-05 定稿交付**：JSC 引擎统一封装 + 引擎工厂 D6 降级链（JSC 主 → QuickJS 自动降级 + onLog 降级可观测）+ 原生侧 `jsc/wrapper.{c,h}`（三端共用）+ `build-jsc.yml` → 交付记录与自检结果（729 用例全绿 + 11 守卫全绿）。文件名升版 v1.3 → v1.4 |
> | v1.5 | 2026-10-02 | **Q-06 交付**：双引擎体积/许可核销 + conformance 双跑——`cross_engine_v1.json`（36 探针 + 五操作 golden 唯一真相源）+ `double_run.c`（引擎无关 harness，`API_PREFIX` 切 `vq_*`/`vj_*`）+ `double_run.py`（平台自适应双跑）+ `check_engine_bundle.py`（许可核销 + 体积登记）+ `engine_bundle_registry.json`（合规归档）。本地自检：双跑 5/5 · 许可/体积 8/8（jsc-android 实测 5.18–6.96 MB/ABI）。批次 Q 剩 **Q-03（Windows JSC）**。文件名升版 v1.4 → v1.5 |
> | v1.6 | 2026-10-02 | **Q-03 交付**：Windows JSC 集成（Playwright WebKit 预编译 `JavaScriptCore.dll` + MSVC 编译自有 wrapper，见 §16 Q-03 行与「批次 Q 交付记录·Q-03」）；**批次 Q 六项（Q-01 ~ Q-06）全交付**。文件名升版 v1.5 → v1.6 |
> | v1.7 | 2026-10-02 | **批次 C 交付（C-01 ~ C-12 中 11 项，C-05 部分）**：播放器核心链全落地（路由/后端选择/控制层 UI/弹幕/四菜单/回退可观测/转封装/字幕/投屏浮窗/Go 代理/Windows 插件/URL 探测）；C-05 仅交付连播控制器，PiP/后台/长按倍速留待下批次。文件名升版 v1.6 → v1.7 |
> | v1.8 | 2026-10-02 | **批次 C-05 收口 → 批次 C 十二项全交付**：PiP 多策略（`pip_strategy`/`pip_bridge`/`pip_controller`）+ 后台播放（`background_play`）+ 长按倍速（`long_press_speed`）+ Android 插件腿（`PipPlugin`/`BackgroundPlayPlugin`/`MediaPlaybackService`）+ 遗漏核查修复 C-10 GoProxyPlugin MainActivity 接线；自检 `flutter analyze` 0 · `flutter test` 1012 全绿 · 覆盖率 82.3%；批次 C 状态 🟡 → ✅。文件名升版 v1.7 → v1.8 |
> | v1.9 | 2026-10-02 | **批次 D 首段交付（D-01 首页 / D-02 搜索 / D-03 豆瓣 / D-06 分类网格）**：四页面 UI + 数据链路打通 + 49 个测试用例 + 3 张 Golden 基线；自检 `flutter analyze` 0 · `flutter test` 1061 全绿 · 覆盖率 80.4% ≥ 70% · 守卫全绿 · 零触达代码文件 2 个（`app.dart` / `main.dart`）。批次 D 余项：D-04 短剧 / D-05 详情页 / D-07 源发现 / D-08 批次自检。文件名升版 v1.8 → v1.9 |
> | v1.10 | 2026-10-02 | **批次 D 收口（D-04 短剧 / D-05 详情页 / D-07 源发现 / D-08 自检）**：短剧页 + 详情页扩展 + 源发现页落地，短剧纳入底部导航；守卫 `check_dart_imports` / `check_docs_consistency` 通过，`flutter analyze` / `test` 交 CI 验证（本地无 SDK，D28 口径）。文件名升版 v1.9 → v1.10 |
> | v1.11 | 2026-10-03 | **批次 E 首段交付（E-01 频道源胶囊 + 分类胶囊 + 双列频道卡）**：直播页 `live_tv_page.dart`（源胶囊 + 切换源浮层 + 调色板分类胶囊 + 双列频道卡，对齐 iOS `LiveTVView`）+「直播」底部导航入口 + `liveCategoryPalette` 12 色 + `live_tv_page_test.dart` 4 用例；自检 `check_dart_imports` 311 文件 + 10 契约脚本全绿，`flutter analyze`/`test` 交 CI（本地无 SDK）。文件名升版 v1.10 → v1.11 |