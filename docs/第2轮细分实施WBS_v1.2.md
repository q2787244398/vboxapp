# vbox 第 2 轮细分实施 WBS · v1.2（任务级）

> **定位**：把 [第2轮开发计划_功能补全_v2.5.md](computer:///workspace/vboxapp/docs/第2轮开发计划_功能补全_v2.5.md) 的**批次级方案**下沉为**任务级可执行清单**（可直接开工/派工/验收）。不替代方案文档。
> **事实依据**：[第2轮开发方案_iOS全量复核_v1.3.md](computer:///workspace/vboxapp/docs/第2轮开发方案_iOS全量复核_v1.3.md) 四轮复核（185/185 文件枚举 + 契约/数据层真值）。
> **状态标注**：**新建**（从零做）· **改造**（Flutter 已有基建，改）· **复用**（已有，直接用）· **移植**（从 iOS 迁语义/资源）。
> **任务编号**：`批次-序号`（如 `A-03`）；共 **128 个任务条目**。
> **v1.1 变更**：① 落定 **D6**（三端均集成 JSC）→ 改写 B-05、新增 **B-05a**、新增 **批次 Q（JSC 三端集成）**；② 修正 v1.0 的任务计数（原写 131，实测 **121**；加 B-05a 与批次 Q 后为 **128**）。
> **v1.2 变更（D24/D25，2026-10-01）**：**批次 A（设计基座 A-01 ~ A-13）代码侧全量交付** → 写入交付记录与全量自检结果；补齐 A-12 遗漏项「35 张 iOS UI 图归档」至 `docs/ui_baseline/ios_ref/`（35 文件 + manifest.json 页面族映射，19 族全中）。文件名升版 v1.1 → v1.2（旧名 `第2轮细分实施WBS_v1.1.md` 仅存于各文档历史沿革行——`is_history` 豁免口径；**现行**引用已全部改指 v1.2）。
> **完成判定**：每批次任务全 Green + 批次自检（analyze 0 / 单测 / 守卫 / Golden）通过。
> **批次 A 交付记录（2026-10-01，遗漏核查后终版）**：A-01 ~ A-13 代码侧全部交付。全量自检：`flutter analyze` 0 issues · `flutter test --coverage` **658 用例全通过** · 整体覆盖率 **75.6% ≥ 70%** · **11 个守卫脚本全绿**（含 `check_ui_tokens --selftest` 负向自测）· conformance **45/45** · Golden 基线 **4 张**像素锁定（home_portrait / home_landscape / grid_landscape / **story_page 组件画廊**）· **35 张 iOS UI 图已归档** `docs/ui_baseline/ios_ref/`（manifest.json 19 页面族映射全中）。**本轮遗漏核查补齐 2 项**：① A-12「35 图归档」（原只建机制未归档）；② A-04「组件 Story 页」（`vbox_story_page.dart`，9 区块全组件陈列 + 4 单测 + Golden）。A-12「逐页 SSIM ≥0.95」机制（`scripts/visual_regression.py`）已就绪，**逐页相似度分在后续批次页面族完善后按 manifest 配对产出**（当前 Flutter 侧仅首页 / 书架成形，无同名页对可比）；A-09「D-pad 焦点全程可见」已达框架层（FocusRing + 焦点遍历组 + 自动聚焦），页面级焦点环铺设随各页面族落地。

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

## 2. 批次 B · 远程源与 Spider（B-01 ~ B-12，含 B-05a）· 13 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| B-01 | manifest 探测 / 缓存（版本→TTL→强制刷新→兼容门控） | `lib/data/datasources/remote/remote_source_config_manager.dart` | A-06 | `remote_default_*` 9 键 | 版本未变不进全量 | 改造 |
| B-02 | 代理降级链（可配置常量） | 同上 | B-01 | — | 主通道失败自动切换 | 新建 |
| B-03 | 6 合 1 聚合解析 | 同上 | B-01 | — | 站点聚合正确 | 新建 |
| B-04 | 站点模式判定 + Node 站点识别 | `lib/domain/usecases/resolve_site_mode.dart` | B-03 | — | 全分支用例 | 新建 |
| B-05 | **引擎映射（D6）**：JS 站点脚本 → **JSC 为主引擎**、**QuickJS 为降级备份**；Node / NodeLX / Python 分流 | `lib/platform/spider/spider_engine_factory.dart` | B-04, **Q-05** | — | 映射表用例；**JSC 不可用时自动降级 QuickJS 且降级可观测**；5 类引擎均有五操作用例 | **改造** |
| B-05a | **JS 全局 API 桥补齐（6 项，与引擎无关）**：`console`/`print` 真实输出（接日志）· `atob`/`btoa` · `req` 别名 · **对象式 `options` 归一** | `lib/platform/spider/spider_js_globals.dart` | B-04 | — | 6 项逐项单测；内置脚本零改动可跑 | 新建 |
| B-06 | QuickJS 引擎接入（**降级备份**位） | `lib/platform/runtime/quickjs_bridge_engine.dart` | B-05 | — | 五操作跑通 | 复用 |
| B-07 | Node / NodeLX 引擎接入（`nodejs_` / lx） | `lib/platform/spider/node_bridge_engine.dart` | B-05 | `remote_node_bundle_url` `remote_node_bundle_ver` | 五操作跑通 | 复用 |
| B-08 | Python 引擎接入（`csp_`） | `lib/platform/spider/python_bridge_engine.dart` | B-05 | — | 五操作跑通 | 复用 |
| B-09 | HTTP 桥：超时 + **5 级编码链（GBK/GB2312/GB18030/Big5/UTF-8）** + `sslBypass`(仅福利) + cookie（**JSC 侧已有现成实现，直接移植**） | `lib/platform/spider/spider_abi.dart` 等 | B-05 | — | GBK/Big5 负向用例 | 改造 |
| B-10 | 容错解码 + `urls ?? [url]` 回填 | `lib/data/datasources/remote/*` | B-09 | — | 负向单测 | 改造 |
| B-11 | 站源原生搜索（Dart HTML 解析） + 腾讯原生 Spider | `lib/domain/usecases/*` | B-09 | — | 与 iOS 结果一致 | 移植 |
| B-12 | conformance：扩五操作 + 站点模式 + manifest 契约 + **双引擎一致性（JSC 主 / QuickJS 降级）** | `conformance/*` · `test/conformance/*` | B-05~11, Q-05 | — | 100% 通过；双引擎结果一致 | 改造 |

---

## 3. 批次 C · 播放器（C-01 ~ C-12）· 12 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| C-01 | 路由 → 后端选择（三端差异化） | `lib/platform/player/player_controller.dart` | B | — | 三端可加载 | 改造 |
| C-02 | 横竖双态控制层 UI（对齐播放器 UI 图） | `.../player/*_controls.dart` | A-07 | — | Golden ≥0.95 | 新建 |
| C-03 | 弹幕渲染 + 设置面板（含自定义弹幕源） | `.../player/danmaku/*` | C-02 | `custom_danmaku_source_enabled` `custom_danmaku_source_url` | 开关/透明度/字号/区域生效 | 新建 |
| C-04 | 选集 / 画质 / 倍速 / 后端切换菜单 | `.../player/*_panel.dart` | C-02 | — | 与图一致 | 新建 |
| C-05 | PiP（多策略）+ 后台播放 + 连播 + 长按倍速 | `.../player/pip/*` | C-01 | `player_pip_enabled` `player_background_play` `player_auto_play_next` `player_long_press_speed` | 行为对齐 iOS | 新建 |
| C-06 | 回退链 + 降级可观测 | `player_controller.dart` | C-01 | — | 降级路径单测 + 日志 | 改造 |
| C-07 | 转封装代理（**端口 18081**，MKV/FLV→fMP4 只换容器） | `lib/platform/player/remux_proxy.dart` | C-01 | — | MKV/FLV 可播 | 新建 |
| C-08 | 字幕解析 + 加载字幕 | `.../player/subtitle_parser.dart` | C-02 | — | 字幕显示正确 | 移植 |
| C-09 | 投屏 / AirPlay 等价 + 非 AVPlayer 内核浮窗 | `.../player/cast/*` `floating/*` | C-01 | — | 可用 | 新建 |
| C-10 | Go 代理三端绑定（分片重写 + Base64 + 缓存） | `go-proxy/` 集成 | C-07 | — | 三端跑通 | 改造 |
| C-11 | **Windows 播放器插件**（C++）+ 核验 macOS `PlayerPlugin.swift` | `windows/runner/player_plugin.*` · `macos/Runner/PlayerPlugin.swift` | C-01 | — | 两端可播 | **新建** / 复用 |
| C-12 | `MediaURLChecker` 播放前 URL 探测 + MPV 后端矩阵（自动/MPV/自由度） | `lib/platform/player/*` | C-01 | — | 探测与后端选择用例 | 移植 |

---

## 4. 批次 D · 内容浏览（D-01 ~ D-08）· 8 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| D-01 | 首页（轮播 + 分类胶囊 + 横向列表）+ 切换源浮层 | `.../pages/home/*` | A-08, B, C | — | Golden ≥0.95 | 改造 |
| D-02 | 搜索（空态：历史/榜单；结果态：左源列表 + 结果卡） | `.../pages/search/*` | B | `searchHistory` | Golden ≥0.95 | 新建 |
| D-03 | 豆瓣（首页 / 榜单 / 分类浏览，并发拉取） | `.../pages/douban/*` | B | — | 三页 Golden | 新建 |
| D-04 | 短剧（列表 + 详情） | `.../pages/short_drama/*` | B, C | — | Golden ≥0.95 | 新建 |
| D-05 | 详情页（头图 / 演员 / 网盘源 chips / 剧集宫格 / 剧集展开 / 下载选择） | `widgets/detail_page.dart` 扩展 | A, B, C | — | Golden ≥0.95 | 改造 |
| D-06 | 分类网格（源下拉 + 分类胶囊 + 三列海报） | `.../pages/category/*` | B | — | Golden ≥0.95 | 新建 |
| D-07 | 源发现页 | `phone/remote_source_page.dart` 扩展 | B | — | 可达且正确 | 改造 |
| D-08 | 批次自检 | — | D-01~07 | — | 全绿 | — |

---

## 5. 批次 E · 直播（E-01 ~ E-06）· 6 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| E-01 | 频道源胶囊 + 分类胶囊 + 双列频道卡 | `.../pages/live/*` | A, C | `live_tv_current_source` | Golden ≥0.95 | 新建 |
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

## 16. 批次 Q · JavaScriptCore 三端集成（D6）（Q-01 ~ Q-06）· 6 项

| 编号 | 任务 | 产出 | 依赖 | 契约 | 验收 | 状态 |
|------|------|------|------|------|------|------|
| Q-01 | **Windows 自建/集成 JSC 可行性评估（门禁）** | `docs/评估_JSC_Windows可行性.md` | — | — | 产出：可用构建方案 + 体积/许可结论；**不通过 → 触发 D6 降级预案（Windows 改用 QuickJS，回老板确认）** | 新建 |
| Q-02 | Android JSC 集成（预编译 `.so` + JNI + CMake，四 ABI） | `android/app/src/main/jni/**` · `CMakeLists.txt` | **Q-01** | — | 四 ABI 可加载；FFI smoke 通过 | 新建 |
| Q-03 | Windows JSC 集成（MSVC 构建 + runner 打包） | `windows/runner/jsc/**` | **Q-01** | — | 可加载；随安装包分发 | 新建 |
| Q-04 | macOS JSC 集成（系统 `JavaScriptCore.framework`，零构建） | `macos/Runner/JSCCorePlugin.swift` | **Q-01** | — | 可加载 | 新建 |
| Q-05 | JSC 引擎统一封装 + 接入引擎工厂（含降级开关与可观测） | `lib/platform/runtime/jsc_bridge_engine.dart` | Q-02~04 | — | 三端同一 ABI；降级可观测 | 新建 |
| Q-06 | 双引擎体积与许可核销 + conformance 双跑 | `scripts/*` · `conformance/*` | Q-05, B-12 | — | 体积登记；LGPL 合规结论；双跑 100% | 新建 |

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