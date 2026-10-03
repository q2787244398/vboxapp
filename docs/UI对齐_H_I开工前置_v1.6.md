# vbox · H / I 批次开工前置 UI 对齐清单

> **版本**：v1.6 · 2026-10-03（v1.6 递增：**C1「SSIM 接入 CI」已交付并验证** —— 新增 `visual-regression` job + 配对清单 `visual_pairs.json` + 脚本清单模式；门禁口径经实测修正为**相对基线**（绝对 0.95 跨设备不可达，留待 J.3 终检）。C 批次 1/5 完成）
> **定位**：**表现层开工前置清单**，与 [UI对齐基准_v1.0.md](UI对齐基准_v1.0.md) 平行存在、互不覆盖。
> **不变式**：本文件**不回溯修改** D1（契约共享）/ D3（统一 UI + 横竖双形态）/ D5（形态判定）—— 三者保持原样；仅把「H / I 批次开工前必须先做完的事」固化为可核对清单。**唯一例外**：§1.5(1) 记录了一项**用户新决策**（全端统一底栏），该决策**须另行登记**到计划 §3.3，本文件仅如实记录其连带影响。
> **依据（实际核对）**：
> 1. `docs/ui_baseline/ios_ref/` 全部 iOS 基准截图**逐张分析**（本文件 §1 为实测结论）；
> 2. `lib/presentation/` 令牌层与组件库**现状**（本文件 §2 为代码核对结论）；
> 3. [第2轮细分实施WBS_v1.22.md](第2轮细分实施WBS_v1.22.md) 批次 H（H-01~H-08）与批次 I（I-01~I-06）条目；
> 4. [第2轮开发计划_功能补全_v2.18.md](第2轮开发计划_功能补全_v2.18.md) §2 页面族清单 / §3.3 双形态 / §3.6 保真度口径；
> 5. **v1.1 新增**：[ContentView.swift](../vbox/App/ContentView.swift) 福利 Tab 门控 · [MainViews.swift](../vbox/Views/MainViews.swift) 首页「豆瓣推荐」实现 · [AppSettings.swift](../vbox/App/AppSettings.swift) 福利三键默认值；
> 6. **v1.2 新增**：[ContentView.swift](../vbox/App/ContentView.swift#L17-L56) 底栏 Tab 组成与 `visibleTabs` · [L108-L131](../vbox/App/ContentView.swift#L108-L131) 胶囊宽度公式与描边 · [L256-L278](../vbox/App/ContentView.swift#L256-L278) 四皮肤底栏配色 · [ProfileView.swift](../vbox/Views/ProfileView.swift#L416-L420) 宫格入口与 [L504-L665](../vbox/Views/ProfileView.swift#L504-L665) 福利两阶段弹窗与记录过滤；及**全端导航形态决策（用户决策）**。

---

## 0. 结论（TL;DR）

| 区块 | 项目数 | 性质 | 不做会怎样 |
|---|---|---|---|
| **★ 结构性缺口（v1.1 新增 · 最高优先）** | 2 | 首页默认内容 + 底栏 Tab 结构 / 福利门控 | 直接决定 A1 的 TabBar 设计与「I-01 ↔ H-05」联动；**越晚改越贵** |
| **A · 全局观感与结构对齐** | 9 | 改主题层 / 壳层，一次改全端生效 | H/I 页面写完还要回头返工，且「悬浮 TabBar」「5 Tab 结构」等硬还原点缺失 |
| **B · 缺失组件补齐** | 6 | H/I 页面直接依赖，当前不存在 | H/I 只能手写临时布局，违反 R-2/R-3/R-4 或产生散落样式 |
| **C · 验收机制补齐** | 5 | 让「是否对齐」可判定 | H/I 做完也无法证明达标；SSIM 门禁实际未生效 |

**执行顺序（不可倒置）**：A → B → C → 再开 H/I 页面（每页产 Golden 并跑一次 SSIM）。

> **一句话**：H/I 是 UI 面积最大的两批（个人中心 / 登录 / 设置 12 分区 / 福利三栏目 + 三栏目平台网格）。**应在已对齐的地基上新建，而不是先建后改。**
>
> **v1.1 补充（两个结构性缺口，必须先修）**：
> ① **首页默认内容应为豆瓣**，当前是纯站点（Spider）驱动、无源即报错；
> ② **底栏应为 5 Tab（首页 / 短剧 / 直播 / 福利 / 我的）**，当前是硬编码 8 项；且「福利」Tab 的显隐由**个人中心 → 福利专区设置**里的 `welfareEnabled && welfareUnlocked` **双条件**控制。
>
> **v1.2 决策（用户决策 · 待登记）**：**全端（Android / Android TV / Windows / macOS）统一使用「底部悬浮胶囊 TabBar」**，不做左侧 NavigationRail、不做顶栏 Tab；检测到 TV / 桌面时**仅自适应尺寸、宽度与内容列数**。据此，样式基准 07/08 两张图与计划 §3.3「横屏 → 左侧 Rail」口径**作废或需重出**（详见 §1.5(1)）。
>
> **v1.3 回执（本批次交付 · 2026-10-03）**：**A8 / A9 / I-01 / H-05 四项已完成并本地验证通过**（`flutter analyze` 0 issue · `flutter test` 全绿 · 契约/令牌守卫全绿 · conformance 全绿），并补出 **5 Tab 态金色基线**。差距 D1 / D12~D18 关闭，口径 R-6 / R-9~R-13 已可自动核对；剩余 A1~A7 / B / C / H-06·H-07 / I-02~I-05 仍待办（详见 §6）。
>
> **v1.4 回执（本批次交付 · 2026-10-03）**：**A2~A7 主题层收口已完成并本地验证通过**（`flutter analyze` 0 issue · `flutter test` **1528 用例全绿** · 11/11 契约脚本全绿 · conformance 全绿）。差距 **D2 / D3 / D4 / D5 关闭**；A6 审计结论「**无页面级手写卡片**」；**A7 已把 `check_ui_tokens` 接入 CI**（contract-checks 由 10 项 → 11 项），机制 C 的「令牌守卫实效」缺口由此闭合。A 批次 **9 项全部完成**（A1 随 A8 落地、A8/A9 随 v1.3 落地）。剩余 B1·B3~B6 / C1~C5 / H-06·H-07 / I-02~I-05 仍待办（详见 §7）。

---

## 1. 基准截图分析（iOS 还原点实测）

### 1.1 截图清单与可读性

| # | 页面族 | 基准文件 | 可读性 |
|---|---|---|---|
| 1 | 首页 | `vbox首页主页面.PNG` | ✅ 已分析 |
| 2 | 切换源浮层 | `首页页面打开切换源悬浮页面.PNG` | ✅ 已分析 |
| 18 | 分类网格 / 源发现 | `切换源分类数据页面显示.PNG` | ✅ 已分析 |
| 3 | 搜索·空态 | `搜索页面(未搜索资源的时候).PNG` | ✅ 已分析 |
| 4 | 搜索·结果态 | `搜索页面(资源出来结果后的界面).PNG` | ✅ 已分析 |
| 5 | 豆瓣排行榜 | `豆瓣排行榜页面.PNG` | ✅ 已分析 |
| 6 | 短剧 | `短剧页面.PNG` | ✅ 已分析 |
| 7 | 详情页 | `详情页剧集页面顶层数据内容可以上下滑动，底部是对应资源封面图.PNG`（×2） | ✅ 已分析 |
| 8 | 详情·剧集展开 | `详情页剧集列表展开界面.PNG` | ✅ 已分析 |
| 9 | 详情·下载选择 | `详情页剧集列表展开准备下载界面.PNG` | ✅ 已分析 |
| 10 | 个人中心 | `个人中心主页面.PNG` | ✅ 已分析 |
| 11 | 账号登录 | `个人中心账号登陆页面.PNG` | ✅ 已分析 |
| 12 | 设置页 | `整个设置页面可以上下滑动查看更多.PNG` | ✅ 已分析 |
| 13 | 直播 | `直播页面.PNG` | ✅ 已分析 |
| 14 | 网盘授权 | `网盘账号授权页面.PNG` | ✅ 已分析 |
| 15 | 网盘排序 | `网盘排序界面.PNG` | ✅ 已分析 |
| 16 | 福利入口 | `福利专区入口界面.PNG` | ✅ 已分析 |
| 17 | 福利三栏目 | `福利页面直播栏目.PNG` | ✅ 已分析 |
| 17b | 福利·视频栏目 | `福利页面主页面视频栏目.PNG` | ❌ **合规过滤不可读** |
| 17c | 福利·漫画栏目 | `福利页面漫画栏目.PNG` | ❌ **合规过滤不可读** |
| 19 | 福利平台清单 | `福利专区设置页面可上下滑动查看更多.PNG` | ✅ 已分析（超长列表，仅结构可辨） |
| — | Bug 反馈 | `Bug 反馈界面.PNG` | ✅ 已分析 |
| 20 | 播放器 | `播放器界面UI/横屏效果/*.PNG`（7 张）· `播放器界面UI/竖屏效果/*.PNG`（5 张） | ✅ 抽样已分析 |

> **⚠️ 基准缺口（已实测确认）**：福利「视频栏目」「漫画栏目」两张图**确因内容合规过滤无法读取**（与 [计划 §2 注](第2轮开发计划_功能补全_v2.18.md) 一致）。H-06 开工前须先人工确认「直播栏目」版式是否可同构推广，或直接从 iOS 源码 [WelfareHomeView.swift](../vbox/Views/WelfareHomeView.swift) 采样补齐基准。

### 1.2 与 H / I 直接相关的还原点（实测）

#### 图 10 · 个人中心（→ I-01 / G-09）

| 元素 | 实测还原点 |
|---|---|
| 顶栏 | 左「分享」**红色**图标 · 右「设置」**红色**齿轮 |
| 头部 | 居中 Vbox Logo（圆角方形）→ 「vbox 默认账号」+ 编辑铅笔 → 「账号： 199114」（次级灰字） |
| 观看记录 | 分区头 = 左**红色竖条** + 标题，右侧「查看更多 >」；横向卡片，缩略图圆角 ≈12，卡下剧名可截断 |
| 功能宫格 | **3×3**：福利专区 / 我的收藏 / 推送播放 / 分享vbox / 下载管理 / 网盘排序 / 备份还原 / 网络音乐 / Bug 反馈；= **红色图标 + 正文黑字，无卡片边框** |
| 底栏 | **悬浮胶囊 TabBar**，「我的」红色实心选中 |

#### 图 11 · 账号登录（→ I-02）

| 元素 | 实测还原点 |
|---|---|
| 容器 | 底部抽屉、白色、大圆角、顶部小把手 |
| 头部 | 居中 Vbox App 深色圆角图标 → 「欢迎回来」（大字）→ 「登录你的账号继续使用」（次级灰字） |
| 输入框 | 2 个：浅灰底、圆角 ≈12、左侧图标（账号=人像 / 密码=锁）、密码右侧眼睛图标 |
| 按钮 | 「登录 / 注册」圆角 ≈12，**未填写时为浅蓝禁用态** |
| 其他 | 「上级用户： 没有上级用户」（灰底胶囊）· 「取消」（纯文字按钮） |

#### 图 12 · 设置页（→ I-03 / I-04 / I-05）

| 元素 | 实测还原点 |
|---|---|
| 皮肤选择器 | **四选 2×2 卡片**：深色模式 / 浅色模式 / 磨砂模式 / 液态模式，每卡=图标 + 名称 + 说明（强制深色 / 跟随系统…） |
| 分区（实测顺序） | 皮肤 → 设置（自定义源 / 搜索调试面板）→ **TMDB 设置**（封套与演员开关 · 代理地址 · 需要 Token · Token）→ **TG 设置**（频道管理 · 代理地址 · URL/Token）→ **订阅源**（管理/云端/远程 + 地址输入 + 保存/清空）→ **站点诊断**（端口状态检测）→ **切片源**（启用元素切片源 · 管理自定义切片源 · 管理自定义解析器）→ **站点管理**（管理站源[启用/禁用]）→ **存储管理**（缓存管理 256 MB）→ **日志调试**（查看日志 · 开启日志记录）→ **关于/更新**（版本 3.1653 · 检查更新） |
| 行样式 | 统一为：**浅灰分组容器 + 左图标 + 标题 + 副标题 + 右开关/箭头**；分组容器圆角 ≈12 |

> 口径差异提示：WBS I-03 记「12 个设置分区」，实测截图为「皮肤 + 10 个功能分区 + 关于/更新」结构。**落地以截图实测分区为准**，并在 §5 登记。

#### 图 16 / 17 / 19 · 福利专区（→ H-05 / H-06 / H-07）

| 元素 | 实测还原点 |
|---|---|
| 入口弹窗（图16） | 抽屉：顶部左「刷新」红图标 · 右「设置」红齿轮；居中礼物红图标 + 「福利专区」+「管理福利功能」；「启用福利专区」+ 副标题「关闭后福利 Tab 和播放记录将隐藏」+ 红色开关；「密码」行；底部「完成」按钮（浅粉底 / 红字） |
| 三栏目（图17） | 顶部分段：**视频 | 直播 | 漫画**，选中项 = **紫色实心胶囊**（其余灰字）；下方**平台图标网格 4 列**：圆角方形彩色图标 + 名称 |
| 平台清单（图19） | 「福利平台设置（内置源）」标题 + 开关；下方超长列表（100+ 内置平台），每行 = 平台图标 + 名称 + 右开关 |

#### 其他 H/I 会复用到的页面（已交付批次，供回归对照）

| 页面族 | 摘要还原点 |
|---|---|
| 首页（图1） | 三段式顶栏（网格图标 · 灰底搜索胶囊 · 榜单/历史/换肤三图标）→ 轮播（圆角≈20、左下标题、红色当前页码点）→ 分类胶囊（白底 ≈16 带图标）→ 分区头（图标+标题+右箭头）→ 横向海报（角标评分 ★）→ **悬浮胶囊 TabBar** |
| 搜索空/结果（图3/4） | 顶栏 = 灰底搜索胶囊 + 榜单图标 + **红色圆形搜索按钮**；结果态为**左窄栏源列表**（选中 = 红色实心胶囊）+ 右侧结果卡 |
| 详情（图7/8/9） | 头图渐隐 + 居中蓝色「▶ 立即播放」胶囊；分段 Tab（全部/演员/导演/编剧）；网盘源 chips（选中红底）；剧集列表行（深灰半透明小胶囊）；弹窗 = 白底大圆角抽屉 + 顶部把手 + 右上「排序/选择/关闭」三图标 + 4 列 chip |
| 网盘授权/排序（图14/15） | 绿色成功卡（Node 常驻系统 + 就绪胶囊 + 端口 58080）；三段网盘卡（品牌圆标 + 已获取绿胶囊 + 双按钮「扫码/网页兜底」+ 状态行 + 测试按钮）；排序弹窗 = 拖拽手柄 + 品牌圆标 + 分隔线 + 「恢复默认 / 完成」 |
| 直播（图13） | 顶部**彩色源胶囊**（蓝/绿/粉）；分类胶囊（「全部」红底选中）；**双列频道卡**（白底大圆角 + 台标 + 台名 + 「1条线路」） |
| 播放器（图20） | 深底黑；弹幕层（绿字）+ 右上功能图标行（投屏/音量/录制红点/全屏/设置）+ 底部进度条 + 控制行（暂停/下一集/弹幕开关=绿/输入框灰胶囊/1×/蓝光/选集/当前线路蓝字）；竖屏为全屏视频 + 居中字幕 |

### 1.3 跨页共性视觉规律（提炼）

| 规律 | 结论 |
|---|---|
| **底部导航** | 全 5 个 Tab 页一律为**悬浮胶囊 TabBar**（白色胶囊、选中 = 主色实心图标+文字、浮于内容之上）——**不是** Material 全宽 `NavigationBar` |
| **卡片** | 白底 + 大圆角 + 主色阴影（对应 §2.5） |
| **胶囊** | 未选中 = 白底/浅灰底 + 描边；选中 = 主色实心（分类）、或 `#34C759`（榜单）、或紫色（福利分段） |
| **弹窗** | 一律**底部大圆角抽屉 + 顶部把手 + 右上功能图标组**；背景压暗 |
| **输入框** | 浅灰底 + 圆角 ≈12 + 左侧图标 |
| **图标** | SF Symbols 细线风格（口径：Material Icons 语义等价即可） |
| **交互反馈** | 截图中**未见 Material 涟漪**；页面切换为 iOS 推入手感 |

---

### 1.4 专项：首页默认内容 与 底栏 Tab 结构（v1.1 新增 · 高优先）

#### (1) 首页默认内容是**豆瓣**，不是源接口

| 维度 | iOS 实测 | Flutter 现状 |
|---|---|---|
| 首页主体 | [MainViews.swift](../vbox/Views/MainViews.swift#L229-L276) 开篇即 `MARK: - 首页视图（豆瓣推荐）`；`@StateObject doubanService = DoubanService.shared`；首屏并发拉取 **14+ 豆瓣栏目**（影院热映 / 即将上映 / 一周口碑榜 / 最新电影 / 华语口碑剧集 / 热门美剧 / 热门动漫 / 热门韩剧 / 热门日剧 / 热门综艺 / Top250 …）+ 豆瓣背景图代理 | [home_page.dart](../lib/presentation/pages/home/home_page.dart#L49-L85)：`listSites()` → `homeContent(sites.first.key)`，**纯站点（Spider）驱动** |
| 无可用源时 | 豆瓣内容**照常显示**（源码注释：豆瓣首页**始终存活**，避免条件创建/销毁导致卡顿与底栏状态丢失） | 直接 `UnknownFailure('无可用站点')` **报错空态** |
| 源的角色 | 源通过顶部「切换源」浮层 / 搜索结果进入，**不是首页默认内容** | 源是首页**唯一**内容来源 |

> **结论**：这不是"样式还差一点"，而是**首页数据来源模型不同** —— Flutter 首页**缺少豆瓣默认内容链路**。当前 [pages/douban/](../lib/presentation/pages/douban/) 只有豆瓣排行榜页，首页未接入。
> **影响**：D-01「首页」虽已标记交付，但**还原口径不达标**；首页是全端首屏，偏差最显眼，且是 SSIM 逐页终检的必检页。

#### (2) 底栏 Tab 结构与「福利 Tab 门控」

| 维度 | iOS 实测 | Flutter 现状 |
|---|---|---|
| Tab 数量与内容 | 截图实测 **5 个**：首页 / 短剧 / 直播 / 福利 / 我的（图1、图6、图13、图17、图10 五张底栏一致） | [home_shell_page.dart](../lib/presentation/shell/home_shell_page.dart#L63-L100) `_destinations` = **8 个**：首页 / 短剧 / 直播 / **书架** / **远程源** / **网盘** / **日志** / **备份** |
| 缺失 | — | ❌ 缺 **福利**、**我的**（另：UI基准 §4.1 记 6 Tab 含「搜索」，与截图实测 5 Tab 存在口径差异，见 §5-6） |
| 多余 | — | ⚠️ 书架 / 远程源 / 网盘 / 日志 / 备份 —— iOS 侧属「我的」宫格入口或工具页，**不是底栏 Tab** |
| 福利 Tab 门控 | [ContentView.swift](../vbox/App/ContentView.swift#L53)：`if settings.welfareUnlocked && settings.welfareEnabled` → **两条件同时为真才显示** | ❌ **完全未实现**：`_destinations` 为 `static const`；presentation 层**零处引用** `app_welfare_enabled` / `app_welfare_unlocked` |

**福利门控规则（iOS 源码推定）**：

| 键 | 默认值 | 语义 | 证据 |
|---|---|---|---|
| `app_welfare_enabled` | `true` | **总开关** —— 即图16 弹窗里的「启用福利专区」 | [AppSettings.swift](../vbox/App/AppSettings.swift#L114-L116) · L165 |
| `app_welfare_unlocked` | `false` | **密码解锁态** —— 输入 `app_welfare_password` 后置真 | L104-L106 · L163 |
| `app_welfare_password` | `"888888"` | 解锁密码 | L109-L111 · L164 |

规则明细（全部有源码证据）：

1. **Tab 显示条件 = `welfareEnabled && welfareUnlocked`**，缺一即隐藏；
2. **关闭总开关会连带重置解锁态**：`onChange(of: welfareEnabled) { if !newValue { welfareUnlocked = false } }`（[ProfileView.swift](../vbox/Views/ProfileView.swift#L168-L171)）；
3. 弹窗文案随解锁态切换：「管理福利功能」（已解锁）/「输入密码解锁福利内容」（未解锁）（[L517](../vbox/Views/ProfileView.swift#L517)）；
4. 关闭总开关后 **福利 Tab 与播放记录一并隐藏**（图16 副标题「关闭后福利 Tab 和播放记录将隐藏」实证）；
5. 密码校验入口有两处：个人中心弹窗、`RemoteWelfarePasswordSheet`（后者校验通过会**同时**置 `welfareUnlocked = true` 与 `welfareEnabled = true`）。

> **⚠️ 技术要点（必须在 A8 内解决，不能留给 H/I）**：当前壳层用 `int _index` + `switch` 映射内容区（[L103-L112](../lib/presentation/shell/home_shell_page.dart#L103-L112)）。一旦 Tab 列表**动态增删**（福利 Tab 出现 / 消失），下标会**漂移错位** → 必须改为**枚举 / key 驱动**，而非下标驱动。

---

### 1.5 底栏精确规格 与 福利专区交互流程（v1.2 新增 · iOS 源码实测）

#### (1) 全端导航形态决策（用户决策 · 待登记）

> **决策（2026-10-03）**：**全端统一使用「底部悬浮胶囊 TabBar」** —— Android / Android TV / Windows / macOS **都用底栏**，不做左侧 NavigationRail、不做顶栏 Tab。检测到 TV / 桌面时，**只自适应尺寸、宽度与内容列数**，导航形式不变。
>
> **连带影响（须登记，否则后续批次会按旧口径重复实现）**：
>
> | # | 影响对象 | 处置 |
> |---|---|---|
> | 1 | 计划 §3.3「横屏 → 左侧 NavigationRail（同图标 + 同标签）」 | **口径变更登记** |
> | 2 | 样式基准 [07_desktop_home.png](ui_baseline/07_desktop_home.png)（左侧 Rail）· [08_tv_home.png](ui_baseline/08_tv_home.png)（顶栏 Tab） | **作废或按新决策重出** |
> | 3 | [adaptive_scaffold.dart](../lib/presentation/widgets/adaptive/adaptive_scaffold.dart#L88-L120) 的 `form.isLandscape → VboxNavRail` 分支 | **废弃**（横屏也走底栏） |
> | 4 | [ui_mode_resolver.dart](../lib/presentation/ui_mode/ui_mode_resolver.dart#L30-L43) `UiForm{portrait,landscape}` 双形态模型 | **保留** —— 差异只体现在尺寸 / 列数 / 内容最大宽度，不体现在导航形式（与 A-05 收敛口径反而更一致） |
> | 5 | TV 的遥控可达性 | 底栏项须进入 D-pad 焦点遍历；十英尺缩放（1.35×）与胶囊宽度需真机验证（见 §5-11） |

#### (2) 底栏胶囊精确规格（[ContentView.swift](../vbox/App/ContentView.swift) 实测）

| 项 | 规格 | 源码 |
|---|---|---|
| Tab 组成 | 基础 4 项 `[首页, 短剧, 直播, 我的]`；`welfareUnlocked && welfareEnabled` 为真时**在 index 3 插入「福利」** → 最多 **5** 项 | [L50-L56](../vbox/App/ContentView.swift#L50-L56) |
| 顺序 | 首页 · 短剧 · 直播 · **福利** · 我的 | 同上 |
| **宽度公式** | `min(屏宽 − 140, Tab数 × 56 + 28)` → 5 Tab = min(W−140, **308**)；4 Tab = min(W−140, **252**) | [L120](../vbox/App/ContentView.swift#L120) |
| 每 Tab 宽 | **56**；胶囊左右内边距各 **14** | 同上 |
| 形状 | `Capsule()`（全圆角，**非 r20**）+ **1px 描边** | [L124-L127](../vbox/App/ContentView.swift#L124-L127) |
| Tab 文字 | `system(size: **10**, weight: 选中 semibold / 未选中 regular)` | [L108-L110](../vbox/App/ContentView.swift#L108-L110) |
| 图标 | 未选中 outline / 选中 fill（福利 = `gift` / `gift.fill`） | [L32 · L44](../vbox/App/ContentView.swift#L32-L44) |
| 全局隐藏 | `settings.isTabBarHidden` 可整体隐藏底栏 | [L94](../vbox/App/ContentView.swift#L94) |

**四皮肤底栏配色**（[L256-L278](../vbox/App/ContentView.swift#L256-L278)）：

| 角色 | 浅色 / 深色 | 磨砂 | 液态 |
|---|---|---|---|
| 选中色 | `#E11D48` | `#7C3AED` | `#38BDF8` |
| 未选中色 | `systemGray2` | `secondaryLabel` | `white@0.72` |
| 胶囊底 | `systemBackground@0.9` | `secondarySystemBackground@0.62` | `black@0.34` |
| 描边色 | `systemGray4` | `white@0.34` | `white@0.22` |

> 这四组颜色值**已固化在 Flutter 令牌层**（`VboxSkin`）可直接消费；但**宽度公式 / 56 / 10pt / Capsule / 1px 描边 / `isTabBarHidden`** 在 Flutter 侧均无实现。

#### (3) 「个人中心 · 福利专区」完整交互（[ProfileView.swift](../vbox/Views/ProfileView.swift) 实测）

**入口**：个人中心 **3×3 宫格第 1 项「福利专区」**（`gift.fill`）；点击时**重置**密码输入与错误态，再弹出 sheet（[L416-L420](../vbox/Views/ProfileView.swift#L416-L420)）。

**弹窗结构**（`presentationDetents([.medium])` 半高抽屉，[L504-L656](../vbox/Views/ProfileView.swift#L504-L656)）：

```
顶部 padding 26
├─ 居中 gift.fill（44pt，主色）
├─ 标题「福利专区」22pt bold
└─ 副标题 14pt secondary ＝ unlocked ?「管理福利功能」: 「输入密码解锁福利内容」
   （仅已解锁时）左上角「刷新」· 右上角「设置」—— 浮动于头区两侧

未解锁 → 阶段一
├─ SecureField「请输入解锁密码」18pt 居中 · 灰底 · r12 · numberPad
├─ 错误时 13pt 红字「密码错误，请重试」+ 中等震动反馈
└─「确认解锁」主色实心按钮 r12

已解锁 → 阶段二
├─「启用福利专区」16pt + 副标题「关闭后福利Tab和播放记录将隐藏」12pt + 右侧 Toggle（主色）
├─ Divider
├─「密码」行：16pt + 右侧「******」14pt secondary（静态掩码，不可修改）
└─「完成」主色实心按钮 r12 → 关闭 sheet
```

**关键语义（最易做错的 7 处）**：

| # | 语义 | 证据 |
|---|---|---|
| 1 | 解锁**只**置 `unlocked = true`，**不**自动置 `enabled`（个人中心弹窗路径） | [L581-L584](../vbox/Views/ProfileView.swift#L581-L584) |
| 2 | 关闭总开关 → **连带**置 `unlocked = false`（下次需重新输密码） | [L168-L171](../vbox/Views/ProfileView.swift#L168-L171) |
| 3 | 「刷新」「设置」按钮**仅在已解锁时**渲染 | [L523 · L546](../vbox/Views/ProfileView.swift#L523-L556) |
| 4 | 「设置」→ `WelfareSettingsView`（即图19 福利平台清单） | [L651-L655](../vbox/Views/ProfileView.swift#L651-L655) |
| 5 | 「刷新」→ `WelfarePlatformConfigStore.refresh` 刷新**福利远程源**，刷新中显示菊花 | [L658-L665](../vbox/Views/ProfileView.swift#L658-L665) |
| 6 | 关闭总开关后，观看记录中来源前缀 `[福利]` 的记录被**过滤展示（非删除）** | [L843-L844](../vbox/Views/ProfileView.swift#L843-L844) |
| 7 | 福利记录点击 → `WelfareHistoryItem` 桥接 → 全屏播放；平台下线 → 「该福利平台已下线或不可用」 | [L392-L393](../vbox/Views/ProfileView.swift#L392-L393) · [L27-L39](../vbox/Views/ProfileView.swift#L27-L39) |

**完整时序**：
宫格「福利专区」→（未解锁）输密码 → 校验通过置 `unlocked` → 底栏**在 index 3 插入「福利」** → 点「福利」Tab → `WelfareTabGateView` → 福利页三栏目；关闭总开关 → 底栏「福利」立即消失 + `[福利]` 记录被过滤，但 `unlocked` 也被重置。

---

## 2. Flutter 侧现状差距（代码核对）

### 2.1 已对齐 ✅（无需返工）

| 项 | 证据 | 状态 |
|---|---|---|
| 令牌层（颜色 / 字号 10 档 / 圆角 8 档 / 间距 / 阴影） | [colors.dart](../lib/presentation/theme/tokens/colors.dart) · [typography.dart](../lib/presentation/theme/tokens/typography.dart) · [radii.dart](../lib/presentation/theme/tokens/radii.dart) · [spacing.dart](../lib/presentation/theme/tokens/spacing.dart) · [shadows.dart](../lib/presentation/theme/tokens/shadows.dart) | ✅ 已交付 |
| 四皮肤枚举 + 主色 + 配色模式 | `VboxSkin`（light/dark 共用 `#E11D48`，frosted `#7C3AED`，liquid `#38BDF8`） | ✅ 已交付 |
| 大卡片（r20 + 1px 渐变描边 + 主色阴影） | [vbox_card.dart](../lib/presentation/widgets/vbox/vbox_card.dart) | ✅ 已对齐 §2.5 |
| 胶囊（选中 `#34C759` + 同色描边 70%） | [vbox_chip.dart](../lib/presentation/widgets/vbox/vbox_chip.dart) | ✅ 已对齐 §2.5 |
| 按钮（primary / secondary / **danger 红底@10% + r8**） | [vbox_button.dart](../lib/presentation/widgets/vbox/vbox_button.dart) | ✅ 已对齐 §2.5 |
| UI 守卫 R-2 / R-3 / R-4 | [check_ui_tokens.py](../scripts/check_ui_tokens.py)（圆角档位 / 字号档位 / 禁止十六进制散落） | ✅ 可负向拦截 |

> 说明：[UI对齐基准_v1.0.md §6](UI对齐基准_v1.0.md) 的差距 **G1（无令牌层）/ G2（无皮肤切换）已过期**，应随本文件一并修订（见 C5）。

### 2.2 未对齐 ❌（本清单要解决的）

> **v1.4 状态**：本表 **D1~D5 · D7 · D12~D18 已关闭** —— D1 / D12~D18 随 v1.3（A8/A9）关闭；**D2~D5 随 v1.4（A2~A5 主题层收口）关闭**；**D7（3×3 宫格）随 v1.3 的 I-01 / B2 关闭**。仅 **D6 · D8~D11** 待办（渐变头部卡 / 设置行 / 皮肤四选 / 登录弹窗 / 福利分段 + 网格）。下表保留 v1.2 时的**开工前现状**，供回溯。

| # | 还原点（§1.3） | Flutter 现状 | 差距 |
|---|---|---|---|
| D1 | **悬浮胶囊 TabBar** | [vbox_nav.dart](../lib/presentation/widgets/vbox/vbox_nav.dart) 用 Material `NavigationBar`（全宽、非悬浮、indicator 药丸） | 🔴 高 |
| D2 | 页面转场（iOS 推入） | Material 默认转场 | 🟡 中 |
| D3 | 无涟漪点击反馈 | 全部 `InkWell` 带 Material 涟漪 | 🟡 中 |
| D4 | Switch 形态（iOS UISwitch） | Material `Switch` | 🔴 高（I-03 大量） |
| D5 | 滚动回弹 | 平台默认 | 🟢 低 |
| D6 | 主色渐变头部卡（图10） | 令牌 `brandGradient` 已有，**组件无** | 🔴 高（I-01） |
| D7 | 3×3 功能宫格（图10） | **无** | 🔴 高（I-01 / G-09） |
| D8 | 设置分组卡 + 设置行（图12） | 仅 [vbox_section_header.dart](../lib/presentation/widgets/vbox/vbox_section_header.dart)，**无 row / 分组容器** | 🔴 高（I-03） |
| D9 | 皮肤四选 2×2（图12） | **无** | 🔴 高（I-03） |
| D10 | 登录弹窗（图11） | 有通用 `VboxDialog`，**无登录专用布局** | 🔴 高（I-02） |
| D11 | 福利分段控件 + 平台图标网格（图17） | **无** | 🔴 高（H-06） |
| **D12** | **首页默认内容 = 豆瓣**（图1） | [home_page.dart](../lib/presentation/pages/home/home_page.dart#L49-L85) 纯站点驱动；无站点直接报错 | 🔴 高（A9） |
| **D13** | **底栏 5 Tab 结构**（首页/短剧/直播/福利/我的） | [home_shell_page.dart](../lib/presentation/shell/home_shell_page.dart#L63-L100) 硬编码 8 项；缺福利/我的，多书架/远程源/网盘/日志/备份 | 🔴 高（A8） |
| **D14** | **福利 Tab 门控**（`enabled && unlocked`） | 未实现；presentation 层**零引用**福利三键；Tab 列表为 `static const` | 🔴 高（A8 ↔ H-05 ↔ I-01） |
| **D15** | 动态 Tab 的**索引驱动** | `int _index` + `switch`，Tab 动态增删必然错位 | 🔴 高（A8） |
| **D16** | 底栏胶囊**精确规格**（§1.5(2)） | `VboxBottomNav` 用 Material `NavigationBar`；**无**宽度公式、56/Tab、10pt 文字、`Capsule`、1px 描边、`isTabBarHidden` | 🔴 高（A8） |
| **D17** | **福利专区完整交互**（入口 + 两阶段弹窗 + 刷新/设置 + 记录过滤） | 未实现；presentation 层零引用福利三键（§1.5(3) 的 7 条语义全部缺失） | 🔴 高（I-01 ↔ H-05） |
| **D18** | 横屏走 Rail 的分支 | [adaptive_scaffold.dart](../lib/presentation/widgets/adaptive/adaptive_scaffold.dart#L88-L106) `form.isLandscape → VboxNavRail`，与 §1.5(1) 新决策冲突 | 🔴 高（A8 废弃该分支） |

---

## 3. 开工前置清单

### 3.1 A · 全局观感对齐（改主题层，一次生效）

> **v1.4 状态**：**A 批次 9 项全部完成** —— A1（悬浮胶囊形态）随 A8 落地；A8 / A9 随 v1.3 落地；**A2 / A3 / A4 / A5（主题层收口）· A6（卡片审计）· A7（UI 守卫接入 CI）随 v1.4 落地**。A2~A5 统一收口于 [`vbox_theme.dart`](../lib/presentation/theme/vbox_theme.dart)（含 `VboxScrollBehavior`），改一处即全端生效。

| # | 动作 | 目标 | 影响面 | 验收 |
|---|---|---|---|---|
| **A1** | 底部导航重构为**悬浮胶囊 TabBar** | 对齐图1/6/13/17 实测形态（白胶囊 + 主色实心选中 + 浮于内容之上） | 全端所有 Tab 页；I-01「我的」、H TabGate、L 批次底栏隐藏 | Golden：TabBar 悬浮态 + 选中态；`NavigationBar` 用法归零 |
| **A2** | `pageTransitionsTheme` → `CupertinoPageTransitionsBuilder` | iOS 推入转场 | 全端 | 人工：转场方向与回弹 |
| **A3** | 统一 `splashFactory`（去/弱涟漪） | 对齐 iOS 无涟漪 | 所有可点元素 | 人工：点击无 Material 涟漪 |
| **A4** | 统一 Switch 主题（iOS 形态） | 对齐图12/16 开关 | I-03 / H-05 | Golden：开关开/关两态 |
| **A5** | `BouncingScrollPhysics` | iOS 手感（低优先） | 所有滚动页 | 人工 |
| **A6** | 排查绕过 `VboxCard` 手写的卡片 | 保证 r20 + 渐变描边统一 | C/D/E/F/G 既有页面 | 检索 `DecoratedBox` / 手写 `BoxDecoration` |
| **A7** | 确认 UI 守卫在 CI 中执行 | R-2/R-3/R-4 生效 | 全端 | CI 日志 |
| **A8** | **底栏统一化 + 规格对齐 + 门控化**：① **全端（含 TV / 桌面）统一底部悬浮胶囊 TabBar**，废弃 Rail / 顶栏方案（解 D18）；② Tab 组成改为**基础 4 项 `[首页,短剧,直播,我的]` + 按 `welfareEnabled && welfareUnlocked` 在 index 3 动态插入「福利」**（最多 5）；③ 驱动方式由 `int _index` 改为**枚举 / key**（解 D15）；④ 按 §1.5(2) 实现宽度公式 `min(W−140, n×56+28)`、56/Tab、10pt、`Capsule` + 1px 描边、四皮肤配色、`isTabBarHidden`（解 D16） | 解 D13~D16 / D18；对齐 iOS 底栏 | 全端壳层 + `AdaptiveScaffold` 横屏分支废弃；**I-01**（宫格入口）、**H-05**（两阶段弹窗）、L 批次（`isTabBarHidden`） | Golden：**4 Tab 态 + 5 Tab 态**两张；`static const _destinations` / `int _index` / 壳层 `VboxNavRail` 用法归零 |
| **A9** | **首页豆瓣默认内容链路** | 对齐 iOS「首页视图（豆瓣推荐）」14+ 栏目 + 背景图代理；**无可用源时回退豆瓣内容而非报错** | 首页（全端首屏）；D-01 回归 | 首页 Golden + 无源场景不报错（回归用例） |

### 3.2 B · 缺失组件补齐（H/I 直接依赖）

| # | 组件 | 对应还原点 | 规格要点 | 验收 |
|---|---|---|---|---|
| **B1** | `ProfileHeader` 主色渐变头部卡 | 图10 | 渐变 `#3B82F6→#2563EB→#1D4ED8`（令牌已有）+ 圆角 + 主色阴影 | 组件 Story + 单测 + Golden |
| **B2** | `QuickGrid` 3×3 功能宫格 | 图10 | 红图标 + 正文黑字 + **无卡片边框** | Golden：9 格两行 |
| **B3** | `SettingsSection` + `SettingsRow` | 图12 / 图19 | 浅灰分组容器 r12 + 内缩分隔线 + 图标/标题/副标题/右开关/右箭头 | Golden：三种行型（开关 / 箭头 / 输入） |
| **B4** | `SkinPicker` 皮肤四选 2×2 | 图12 | 图标 + 名称 + 说明；选中态描边/填充 | Golden：四皮肤各一张或四态合一 |
| **B5** | `LoginSheet` 登录弹窗 | 图11 | 图标 + 「欢迎回来」+ 2 输入框 + 禁用/可用按钮 + 上级用户胶囊 + 取消 | Golden：空态（禁用）+ 填写态 |
| **B6** | `WelfareSegmentedTabs` + `WelfarePlatformGrid` | 图17 | 分段 = 紫色实心选中；网格 = 4 列圆角方形彩色图标 + 名称 | Golden：三栏目切换 + 网格 |

> 复用既有：`VboxCard` / `VboxChip` / `VboxButton(danger)` / `VboxToast` / `VboxSectionHeader` / `VboxDialog` / `VboxEpisodeChip` / `PosterCard` / `SourceBadge` / `VboxBottomNav`(待 A1 重构)。
>
> **v1.3 状态**：**B2 `QuickGrid` 已完成**（随 I-01 落地）。
>
> **v1.5 状态**：**B3 / B4 / B5 / B6 四项已完成并验证**（详见 §8）——
> · B3 = [vbox_settings.dart](../lib/presentation/widgets/vbox/vbox_settings.dart)（`VboxSettingsSection` + `VboxSettingsRow` 三行型 + `VboxSettingsInputRow`）；
> · B4 = [vbox_skin_picker.dart](../lib/presentation/widgets/vbox/vbox_skin_picker.dart)（`VboxSkinPicker` + `VboxSkinCard`，四皮肤 2×2）；
> · B5 = [vbox_login_sheet.dart](../lib/presentation/widgets/vbox/vbox_login_sheet.dart)（图标 / 欢迎回来 / 2 输入框 / 渐变主按钮 / 上级胶囊 / 取消）；
> · B6 = [vbox_welfare.dart](../lib/presentation/widgets/vbox/vbox_welfare.dart)（`VboxWelfareTabs` 三段选中紫色实心 + `VboxWelfarePlatformGrid` 4 列圆角方形渐变图标）。
> **B1 暂缓**：图10 实测为**居中 Logo**（非顶部渐变头卡），渐变头部卡无 iOS 还原依据 → 降级为「不实现」，待 D6 处置。

### 3.3 C · 验收机制补齐（让"是否对齐"可判定）

| # | 动作 | 现状（实测） | 目标 |
|---|---|---|---|
| **C1** | **把 SSIM 比对接入 CI** | ❌ [flutter-check.yml](../.github/workflows/flutter-check.yml) 中仅有**注释**提及 golden，[visual_regression.py](../scripts/visual_regression.py) **未作为步骤执行**（与 A-08 声称的「CI 接入」不符） | 新增 job：逐页 SSIM 比对 + 阈值失败即红 |
| **C2** | **补 H/I 页面族 Golden** | 现有 Golden 仅覆盖首页/豆瓣/网格/短剧等少数族 | 至少补：图10 / 图11 / 图12 / 图17 / Bug 反馈 |
| **C3** | **补福利视频/漫画栏目基准** | ❌ 两张图合规不可读（§1.1） | 人工确认「直播栏目」版式同构，或从 [WelfareHomeView.swift](../vbox/Views/WelfareHomeView.swift) 采样 |
| **C4** | **R-5 页面登记** | R-5 无自动化，纯人工 | 把 H/I 新页面登记进 [UI对齐基准 §4.1/§4.3](UI对齐基准_v1.0.md) |
| **C5** | **修订 UI 对齐基准至 v1.1** | §6 的 G1/G2 已过期；§4.2「10 文件」不准；§2 未收录实测补充分区 | 出 v1.1 并登记变更 |

> **v1.6 状态**：**C1 已完成并验证**（详见 §9）—— 门禁口径**经实测修正**：计划 §3.6 的绝对 SSIM ≥ 0.95 跨设备不可达（实测 0.25~0.45），故 CI 采用「基线 − 容差」**相对门禁**（防回归），绝对 0.95 留待 J.3 终检重定口径。
> **C2~C5 仍待办**。C2（H/I 页面族 Golden）依赖页面产出 → 随 **I-02~I-05 / H-06·H-07** 逐页接入（每页追加一条 pairing 即可）。

### 3.4 D · 逐页验收表（H / I 直接可用）

| 批次 | 条目 | 基准图 | 必须命中的还原点 | 门禁 |
|---|---|---|---|---|
| I | I-01 个人中心 | 图10 | 顶栏双红图标 / Logo+账号+编辑 / 观看记录（红竖条分区头 + 查看更多）/ **3×3 宫格** / 悬浮 TabBar | Golden + SSIM ≥0.95 |
| I | I-02 登录弹窗 | 图11 | 抽屉 + 图标 + 欢迎回来 + 2 输入框 + 禁用态按钮 + 上级用户胶囊 + 取消 | Golden + SSIM ≥0.95 |
| I | I-03 设置页 | 图12 | **皮肤四选 2×2** + 10 功能分区 + 统一行样式 + 开关形态 | 逐条可用 + Golden |
| I | I-04 显示模式开关 | —（§3.2） | 自动 / 手机竖屏 / 大屏横屏，可强制 | 功能 + 开关形态（A4） |
| I | I-05 自更新 UI | — | 检查 / 下载 / 安装引导 | 功能 + 组件一致性 |
| H | H-05 入口门控 | 图16 | **两阶段**：未解锁 = 礼物图标 + 密码框 + 「确认解锁」；已解锁 = 启用开关 + 密码掩码行 + 刷新/设置 + 「完成」（详见 §1.5(3)） | 功能（关闭后 Tab 与记录隐藏）+ Golden |
| H | H-06 三栏目 + 平台网格 | 图17（+ C3 补图） | 紫色分段选中 + 4 列彩色平台图标网格 | Golden + SSIM ≥0.95 |
| H | H-07 域名/代理设置 | 图19 | 平台清单行（图标+名称+开关）+ 代理/域名输入 | 开关生效 + Golden |
| G | G-09 Bug 反馈 | `Bug 反馈界面.PNG` | 抽屉 + 标题输入 + 详细描述文本域 + 提交按钮 | Golden |

### 3.5 E · 执行顺序

```
★（结构性缺口：A8 底栏统一化·规格·门控 ／ A9 首页豆瓣默认内容）   ← v1.1/v1.2 新增，最先做
  └─► A（全局观感与结构 9 项）
        └─► B（补齐 6 个组件 + Story/单测）
              └─► C（SSIM 接 CI + 补 Golden/基准 + 修订 UI 对齐基准 v1.1）
                    └─► H / I 页面开发（每页产 Golden，随页跑 SSIM）
```

**禁止**：跳过 A/B 直接开 H/I 页面 —— 会产生手写临时布局与散落样式，随后被迫批量返工。

---

## 4. 验收口径

继承 [UI对齐基准 §5](UI对齐基准_v1.0.md) 的 R-1 ~ R-5，并为 H/I 增补：

| 编号 | 规则 | 核对方式 |
|---|---|---|
| **R-6** | 底部导航为**悬浮胶囊 TabBar**，不得使用全宽 Material `NavigationBar` | 检索 `NavigationBar(` + Golden |
| **R-7** | H/I 页面族**必须各有 Golden**，且 SSIM ≥0.95 才能合入 | CI SSIM job |
| **R-8** | 新增页面/组件不得绕过 `Vbox*` 组件库手写等价样式 | 代码评审 + 检索 |
| **R-9** | 底栏为**基础 4 项 + 福利按需插入 index 3**（最多 5），列表**动态可裁剪**、由 key/枚举驱动；且**全端统一为底栏**（TV / 桌面不得改用 Rail / 顶栏） | 检索 `_destinations` / 壳层 `VboxNavRail` + Golden |
| **R-10** | 福利 Tab 显示 = `app_welfare_enabled && app_welfare_unlocked`；关闭总开关须**连带重置解锁态**并隐藏播放记录 | 单测 + 真机 |
| **R-11** | 首页默认内容为**豆瓣**；无可用源时**回退豆瓣**而非报错空态 | 回归用例 + Golden |
| **R-12** | 底栏胶囊宽度 = `min(屏宽−140, Tab数×56+28)`；每 Tab 宽 56；文字 **10pt**；形状 `Capsule` + **1px 描边**；四皮肤配色按 §1.5(2) | Golden + SSIM |
| **R-13** | 福利门控完整语义（§1.5(3) 七条）：解锁**不**自动启用；关闭总开关**连带**重置解锁；刷新/设置仅解锁后可见；记录**过滤非删除** | 单测 + 真机 |

---

## 5. 遗留与风险

| # | 事项 | 影响 | 建议 |
|---|---|---|---|
| 1 | 福利「视频/漫画栏目」基准图不可读 | H-06 三栏目版式无完整基准 | 开工前先做 C3 |
| 2 | SSIM 门禁未真正接入 CI | "≥95% 还原度"当前**无法被拦截** | C1 优先 |
| 3 | UI 对齐基准 §6 现状差距已过期 | 会误导后续批次判断"是否需要令牌层" | C5 修订 |
| 4 | 设置页分区数与 WBS I-03「12 分区」口径不一致 | 验收时易扯皮 | 以截图实测为准并登记 |
| 5 | A 与 B 未完成即开 H/I | 返工面大（含 Golden / 门禁 / 真机验收重跑） | 严格按 §3.5 顺序 |
| **6** | UI基准 §4.1 记 **6 Tab**（含「搜索」），截图实测 **5 Tab** | 底栏结构验收口径冲突 | 以截图实测为准；C5 修订 UI 对齐基准时同步 |
| **7** | 首页 D-01 已标记「交付」，但数据来源模型不符（纯站点驱动、无豆瓣默认） | D-01 需重新判定是否达标 | 纳入 A9；并复核 D-01 的验收记录 |
| **8** | 福利 Tab 门控是**跨批次**联动（A8 壳层 + H-05 门控 + I-01/I-03 入口） | 任一单批做完仍不可用 | 在 WBS 中显式标注跨批次依赖 |
| **9** | 现有 8 项底栏中的 书架/远程源/网盘/日志/备份 需**迁移到「我的」宫格入口** | 直接删除这些 Tab 会导致功能失去入口 | A8 必须与 I-01 宫格（B2）同批规划，先建入口再撤 Tab |
| **10** | 本决策（全端统一底栏）与计划 §3.3 及样式图 07/08 冲突 | 若不登记，后续批次会按 Rail / 顶栏重复实现，产生双份返工 | 变更登记 §3.3；07/08 基准作废或重出 |
| **11** | TV 端改用底栏后，需验证**遥控可达性**与十英尺缩放（1.35×）叠加下的胶囊宽度 | 5×56+28=308 在大屏可能偏窄；底栏项若不在焦点遍历内则遥控无法选中 | 真机验证；必要时按形态放宽 `maxWidth` |

---

## 6. 交付回执

> 按批次累积：**v1.3 批（A8 / A9 / I-01 / H-05）** 见 §6.1~§6.4；**v1.4 批（A2~A7 主题层收口）** 见 §7。

### 6.1 v1.3 · 交付明细（A8 / A9 / I-01 / H-05）

> 对上述四项做「代码 + 测试 + 金色基线」三合一交付。以下为**已核对**的落地证据（本地实跑）。

| 前置/条目 | 状态 | 落地文件 | 核对证据 |
|---|---|---|---|
| **A8** 底栏统一化 | ✅ 已交付 | [app_tab.dart](../lib/presentation/shell/app_tab.dart)（`AppTab` 枚举 + `visibleTabs` 插 index 3）· [vbox_nav.dart](../lib/presentation/widgets/vbox/vbox_nav.dart)（`widthFor = min(W−140, n×56+28)` · 56/Tab · `s10` · `StadiumBorder` + 1px 描边）· [adaptive_scaffold.dart](../lib/presentation/widgets/adaptive/adaptive_scaffold.dart)（`hideTabBar` · 横屏 Rail 分支废弃）· [home_shell_page.dart](../lib/presentation/shell/home_shell_page.dart)（枚举/key 驱动，`_destinations` / `int _index` 归零） | 检索：`NavigationBar(` 0 处 · 壳层 `VboxNavRail` 0 处 · `_destinations` 0 处 |
| **A8** 福利门控 | ✅ 已交付 | [welfare_controller.dart](../lib/presentation/welfare/welfare_controller.dart)（三契约键读写 + 关总开关**连带**重置 `unlocked`）· [welfare_sheet.dart](../lib/presentation/pages/profile/welfare_sheet.dart)（两阶段）· [welfare_gate_page.dart](../lib/presentation/pages/welfare/welfare_gate_page.dart) | 单测覆盖「解锁不自动启用 / 关总开关连带重置」（R-10 · R-13） |
| **A9** 首页豆瓣默认内容 | ✅ 已交付 | [home_page.dart](../lib/presentation/pages/home/home_page.dart)（默认 `DoubanHomeView`）· [douban_home_page.dart](../lib/presentation/pages/douban/douban_home_page.dart) | 首页 Golden + 无源不报错回归用例（R-11） |
| **I-01** 个人中心 | ✅ 已交付 | [profile_page.dart](../lib/presentation/pages/profile/profile_page.dart)（顶栏双主色图标 + 居中 Logo/账号 + 观看记录**红竖条分区头** + **3×3 宫格** + 「更多工具」）· 组件 [vbox_quick_grid.dart](../lib/presentation/widgets/vbox/vbox_quick_grid.dart)（对应 B2） | 宫格第 1 项「福利专区」入口 → H-05；**注**：图10 头部为居中 Logo（非渐变卡），故 **D6/B1 主色渐变头部卡仍待办**（供 I-03 设置页/后续页复用） |
| **H-05** 福利专区两阶段弹窗 | ✅ 已交付 | [welfare_sheet.dart](../lib/presentation/pages/profile/welfare_sheet.dart)（未解锁 = 密码框 + 「确认解锁」；已解锁 = 启用开关 + 密码掩码行 + 「完成」） | Golden + 单测 |

### 6.2 v1.3 · 金色基线（4 Tab 态 + 5 Tab 态）

| 基线 | 态 | 文件 |
|---|---|---|
| `home_portrait` | 4 Tab（默认：福利未解锁） | [home_portrait.png](../test/golden/goldens/home_portrait.png) |
| `home_landscape` | 4 Tab（横屏 → 仍为悬浮胶囊底栏，无 Rail） | [home_landscape.png](../test/golden/goldens/home_landscape.png) |
| **`home_welfare_portrait`** | **5 Tab（福利已解锁，index 3 插入）** | [home_welfare_portrait.png](../test/golden/goldens/home_welfare_portrait.png) |

### 6.3 v1.3 · 验证结果

| 门禁 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze`（Flutter 3.47.5，CI 锁定版） | **0 issue** |
| 全部测试 | `flutter test` | **全绿（1524 用例）** |
| 覆盖率门禁 | `flutter test --coverage` + `check_coverage.py` | **全 lib 口径 77.7% ≥ 70%，达标** |
| 契约/一致性脚本 | CI contract-checks 全 10 项 | **全绿（10/10）** |
| UI 令牌守卫 | `check_ui_tokens.py` | **全绿**（v1.4 起已接入 CI，见 §7） |
| 一致性用例 | `conformance/runner/run_conformance.py` | **全绿** |

### 6.4 v1.3 · 遗留（当时）

- ~~A1~A7~~ → **已在 v1.4 全部完成**（A1 随 A8；A2~A7 随 v1.4，见 §7）。
- **B1~B6**：**B2 宫格**已随 I-01 落地；**B1 主色渐变头部卡（图10 实测为居中 Logo，未使用）/ B3 设置行 / B4 皮肤四选 / B5 登录弹窗 / B6 福利分段 + 网格** —— **待办**（H-06/H-07 / I-02~I-05 阻塞项）。
- **C1~C5**：SSIM 接 CI（C1）、H/I 页面族 Golden（C2）、福利视频/漫画基准（C3）、R-5 登记（C4）、UI 对齐基准升 v1.1（C5）—— **待办**。
- **H-06 / H-07 / I-02~I-05**：**待办**。
- **§5-2（SSIM 门禁未接 CI）· §5-11（TV 遥控可达性）**：**风险仍在**，须在开 H/I 前处置。

---

## 7. v1.4 交付回执（A2~A7 主题层收口 · 2026-10-03）

> 本批次**全部落在主题层 / 机制层**，不改任何页面结构；因此**既有首页 4 张金色基线字节不变**，仅 Story 页因新增开关段而更新。

### 7.1 交付明细

| 前置 | 状态 | 落地 | 核对证据 |
|---|---|---|---|
| **A2** 页面转场 | ✅ | [vbox_theme.dart](../lib/presentation/theme/vbox_theme.dart) `pageTransitionsTheme`：`TargetPlatform` 全 6 项 → `CupertinoPageTransitionsBuilder` | 单测：遍历 `TargetPlatform.values` 断言均为 Cupertino |
| **A3** 去涟漪 | ✅ | 同上 `splashFactory: NoSplash.splashFactory`（按下高亮保留，对齐 iOS「无扩散波纹」） | 单测：`theme.splashFactory == NoSplash.splashFactory` |
| **A4** 开关主题 | ✅ | 同上 `switchTheme`：滑块恒白 / 选中轨道 = 皮肤主色 / 未选中 = `systemGray4` / 描边透明 | 单测：4 皮肤 × 2 亮度共 8 组断言（R-1 口径）；Story 页补开关两态 |
| **A5** 滚动回弹 | ✅ | 同上新增 `VboxScrollBehavior`（`BouncingScrollPhysics` + 抑制 `GlowingOverscrollIndicator`）；[app.dart](../lib/app.dart) 经 `MaterialApp.scrollBehavior` 接入 | 单测：物理类型 + `buildOverscrollIndicator` 原样返回 child |
| **A6** 卡片审计 | ✅ | 全 `lib/presentation` 检索 `boxShadow`（共 4 处）与 `BoxDecoration`：**未发现页面级手写卡片**（R-8 无违规）；2 处非卡片手写阴影登记为观察项（见 §7.3） | 检索结论 + §7.3 |
| **A7** UI 守卫接入 CI | ✅ | [flutter-check.yml](../.github/workflows/flutter-check.yml) contract-checks **10 项 → 11 项**（新增 `check_ui_tokens`），job 名与文件头注释同步 | 本地守卫全绿 + `--selftest` 负向自测全通过；CI 生效 |

### 7.2 验证结果（本地实跑）

| 门禁 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze` | **0 issue** |
| 全部测试 | `flutter test` | **全绿（1528 用例，较 v1.3 +4）** |
| 契约/一致性脚本 | 11 项（含新增 `check_ui_tokens`） | **全绿（11/11）** |
| UI 令牌守卫 | `check_ui_tokens.py`（扫描 264 文件）+ `--selftest` | **全绿**（R-2 / R-3 / R-4 负向自测全通过） |
| 金色基线 | `flutter test test/golden --update-goldens` 后比对 | 仅 `story_page.png` 变化；**首页 4 张字节不变** |

### 7.3 A6 审计明细（观察项 · 不阻塞）

| 位置 | 写法 | 判定 |
|---|---|---|
| [login_sheet.dart](../lib/presentation/pages/cloud/login_sheet.dart#L197-L207) 二维码卡 | 手写 `BoxShadow`（blur 12 / offset (0,6) / 8%） | 非通用卡片（对齐 iOS `qrCard` 专用）；圆角已走 `VboxRadii.r16`；**阴影未走 `VboxShadows`** → 观察项 |
| [mini_player.dart](../lib/presentation/widgets/music/mini_player.dart#L228-L238) 迷你播放器浮层 | 手写 `BoxShadow`；折叠态圆角 `22`（条件表达式，未触发 R-2 守卫） | 浮层非卡片；折叠态 `22` 属「胶囊」语义 → 观察项 |
| 其余各处 `BoxDecoration` | 渐变蒙层 / 圆形页码点 / 聚焦环 / 分隔线 | 非卡片，**合规** |

> 处置：两项观察项均位于**既有已交付页面**（批次 F / G），改动会牵动既有视觉，按 R-5 须走登记流程；本批次**仅登记不改**。

### 7.4 v1.4 遗留（按 §3.5 顺序继续）

- **B1 · B3~B6**：渐变头部卡 / 设置行（`SettingsSection` + `SettingsRow`）/ 皮肤四选 / 登录弹窗 / 福利分段 + 平台网格 —— **待办**（H-06 / H-07 / I-02~I-05 阻塞项）。
- **C1~C5**：SSIM 接 CI（C1）· H/I 页面族 Golden（C2）· 福利视频/漫画基准（C3）· R-5 登记（C4）· UI 对齐基准升 v1.1（C5）—— **待办**。
- **H-06 / H-07 / I-02~I-05**：**待办**。
- **§5-2（SSIM 门禁仍未接 CI）· §5-11（TV 遥控可达性）**：**风险仍在**，须在开 H/I 前处置。

### 7.5 批次遗漏检查（本批发现 · 逐项处置）

| # | 发现 | 性质 | 处置 |
|---|---|---|---|
| 1 | CI step 名写死 `conformance runner (45 checks)`，实测为 **83 项**（`合计 83 项：通过 83 · 失败 0`） | 注释不实（数字会随 fixture 增长漂移） | ✅ **本批修正**：step 名改为 `Run conformance runner`（去写死数字，以 runner 输出为准） |
| 2 | [README.md](../README.md) 目录表写 `conformance/（45 项）` | 既有文档漂移 | 📌 登记；随 **C5**（UI 对标基准升版）同期修订 |
| 3 | 主方案 [VBOX_PLAN_v6.47.md](VBOX_PLAN_v6.47.md) 多处**仍写**陈旧口径「10 个校验脚本」「conformance 45 项」（L30 / L3568 / L3749 / L3888 / L5427 等） | 既有文档漂移 | 📌 登记；主方案走其自身版本治理（规则 6/7），**不在本清单改动范围** |
| 4 | `login_sheet.dart` / `mini_player.dart` 手写阴影 | 非卡片的样式观察项 | 📌 已登记（§7.3），按 R-5 走登记流程后处理 |

> 回溯口径：§7.3 与 §7.5 的 📌 项**均不阻塞** H/I 开工；但若开 H/I 前未清，须在批次计划中显式承接。

---

## 8. v1.5 交付回执（B3~B6 缺失组件补齐 · 2026-10-03）

### 8.1 交付清单

| # | 交付物 | 文件 | 关键内容 |
|---|---|---|---|
| B3 | 设置分组 + 三行型 | [vbox_settings.dart](../lib/presentation/widgets/vbox/vbox_settings.dart) | `VboxSettingsSection`（浅灰分组容器 r16 + 内缩分隔线 `n−1`）+ `VboxSettingsRow`（开关 / 箭头两行型，静态工厂 `toggle` / `navigation`）+ `VboxSettingsInputRow`（内嵌输入框） |
| B4 | 皮肤四选 2×2 | [vbox_skin_picker.dart](../lib/presentation/widgets/vbox/vbox_skin_picker.dart) | `VboxSkinPicker`（默认 2 列）+ `VboxSkinCard`（选中填皮肤渐变 / 未选中二级分组底 95%，浅色卡取深字） |
| B5 | 登录弹窗 | [vbox_login_sheet.dart](../lib/presentation/widgets/vbox/vbox_login_sheet.dart) | 72×72 图标（兜底蓝色渐变闪电）/「欢迎回来」/ 副标题 / 卡片 r20（hShadow 8%）/ 账号 + 密码输入（浅灰 r12 + 蓝图标）/ 蓝色横向渐变主按钮（空账号或加载中 → 透明 60%）/ 上级用户胶囊 / 取消 |
| B6 | 福利分段 + 平台网格 | [vbox_welfare.dart](../lib/presentation/widgets/vbox/vbox_welfare.dart) | `VboxWelfareTabs`（三段等宽，选中 = r12 实心渐变 + 白字，「直播」为紫色）+ `VboxWelfarePlatformGrid`（4 列，52×52 圆角 16 渐变方块 + 12 medium 名称） |
| — | 令牌扩展 | [colors.dart](../lib/presentation/theme/tokens/colors.dart) / [spacing.dart](../lib/presentation/theme/tokens/spacing.dart) | 登录渐变 + 强调色 · 系统灰 6 / 分组底（明暗）· 福利三段渐变 · 平台 8 色板 + `welfarePlatformGradient()` 稳定哈希 · `segmentVertical` / `inputHorizontal` |
| — | 导出 / Story / 单测 / Golden | [vbox.dart](../lib/presentation/widgets/vbox/vbox.dart) · [vbox_story_page.dart](../lib/presentation/widgets/vbox/vbox_story_page.dart) · [vbox_components_test.dart](../test/presentation/widgets/vbox/vbox_components_test.dart) · [vbox_story_page_test.dart](../test/presentation/widgets/vbox/vbox_story_page_test.dart) · [story_page.png](../test/golden/goldens/story_page.png) | 新组件导出；Story 页新增 B5 / B6 两区块（**共 14 区**）；新增单测 **9 例**（B5 六 / B6 三）；金色基线 `story_page.png` 更新 |

### 8.2 验证结果（本地实跑 · Flutter 3.47.5 / Dart 3.13.4）

| 门禁 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze` | **0 issue** |
| 全部测试 | `flutter test` | **全绿（1549 用例，较 v1.4 +21）** |
| 契约/一致性脚本 | 11 项（含 `check_ui_tokens`） | **全绿（11/11）** |
| conformance | `run_conformance.py` | **全绿（83/83）** |
| UI 令牌守卫 | `check_ui_tokens.py`（扫描 268 文件） | **全绿（R-2 / R-3 / R-4）** |
| 金色基线 | `flutter test test/golden --update-goldens` 后比对 | 仅 `story_page.png` 变化（视口 4000→6400，新增两区块）；**首页 5 张字节不变** |

### 8.3 规格要点与近似说明

- **B6 平台图标配色不可复现**：iOS 用 `abs(name.hashValue) % 8`，而 Swift `String.hashValue` **每进程随机**（截图配色因此不可复现）；Flutter 改用**稳定求和哈希**，保证同名平台跨运行一致。
- **图17 实测修正**：分段选中为**紫色实心圆角胶囊**、网格为**圆角方形**渐变图标（非圆形）——与 `RemoteWelfareHomeView` / `RemotePlatformIconCard` 源码一致，已按其实现。
- **字号档位取整**：iOS 登录标题 26 → 取 **24**；按钮 17 → 取 **18**（大号按钮档）；均受 R-3 档位约束。

### 8.4 遗留（按 §3.5 顺序继续）

- **B1**：渐变头部卡 —— **降级为不实现**（图10 实测为居中 Logo，无还原依据），随 D6 处置。
- **C1~C5**：SSIM 接 CI（C1）· H/I 页面族 Golden（C2）· 福利视频/漫画基准（C3）· R-5 登记（C4）· UI 对齐基准升 v1.1（C5）—— **待办**。
- **H-06 / H-07 / I-02~I-05**：**待办**（B3~B6 已解其组件阻塞）。

---

## 9. v1.6 交付回执（C1 · SSIM 接入 CI · 2026-10-03）

### 9.1 交付清单

| 交付物 | 文件 | 内容 |
|---|---|---|
| CI job | [flutter-check.yml](../.github/workflows/flutter-check.yml#L82-L102) | 新增 `visual-regression` job：`pip install opencv-python-headless==4.13.0.92 numpy==2.2.6`（与本地生成基线**同版本固定**，保证 SSIM 可复现）→ 跑 `visual_regression.py --pairs … --gate` |
| 配对清单 | [visual_pairs.json](ui_baseline/visual_pairs.json) | 每页一条：`family` / `ref`（iOS 基准图）/ `cmp`（Flutter golden）/ `baseline`；顶层 `tolerance = 0.02`。首批接入 **2 对** |
| 脚本清单模式 | [visual_regression.py](../scripts/visual_regression.py) | 新增 `--pairs` 清单模式（+ `--update-baseline` 登记实测分）；保留原 `--ref/--cmp` 目录模式（向后兼容） |

### 9.2 门禁口径（**实测修正** · 决策 A）

> ⚠️ **计划 §3.6 的绝对 SSIM ≥ 0.95 不可用于 CI 门禁** —— 实测 iOS 真机截图 vs Flutter 金色基线：

| 页面 | ref（iOS） | cmp（Flutter golden） | 实测 SSIM |
|---|---|---|---|
| 首页 | `vbox首页主页面.PNG`（2556×1179） | `home_portrait.png`（390×844） | **0.449** |
| 豆瓣排行榜 | `豆瓣排行榜页面.PNG`（2556×1179） | `douban_ranking.png`（390×844） | **0.254** |

差异来源：分辨率 / 字体光栅化 / **内容**（真实海报 vs 占位图）三重差异 —— **布局完全一致也不可能达标**。故 C1 落地为**相对门禁**：

- 通过条件：`SSIM ≥ baseline − tolerance`（`tolerance = 0.02`）
- 失败：跌破即红（**回归即红**，防止把已做好的 UI 改坏）
- 绝对 0.95 口径**留待 J.3「UI 还原度逐页终检」**重定（需先解决内容差异，例如只比页面主体区域 / 掩码内容，见计划 §5 风险「视觉回归基线不稳定」）

### 9.3 验证结果（本地实跑）

| 项 | 命令 | 结果 |
|---|---|---|
| 登记基线 | `--pairs … --update-baseline` | ✅ 写入 2 条（0.4494 / 0.2539） |
| 正向门禁 | `--pairs … --gate` | ✅ **exit 0** |
| 负向门禁 | 人为抬高基线至 0.60 → `--gate` | ✅ **exit 1**（`首页 Δ −0.151 · 低于基线-容差 0.580`） |
| 向后兼容 | `--ref … --cmp …`（目录模式） | ✅ 行为不变 |
| YAML 合法性 | `yaml.safe_load` | ✅ 7 个 job 解析正常 |
| 契约脚本 | 11 项 | ✅ **11/11 全绿**（含 `check_docs_consistency`） |

### 9.4 后续接入方式（每页一步）

1. 页面产出 Flutter 金色基线（`flutter test --update-goldens`）；
2. 在 [visual_pairs.json](ui_baseline/visual_pairs.json) `pairs` 追加一条（`baseline` 留 `null`）；
3. 跑 `python3 scripts/visual_regression.py --pairs docs/ui_baseline/visual_pairs.json --update-baseline` 登记实测分；
4. 提交 —— 该页自此进入 CI 回归门禁。

### 9.5 遗留

- **C2**：H/I 页面族 Golden —— 随页面开发**边做边接**（依赖 I-02~I-05 / H-06·H-07）。
- **C3 / C4 / C5**：待办。

---

> **维护口径**：本文件与主方案**版本独立**（主方案用 v6.x，UI 对齐基准用 v1.x，本文件用 v1.x 独立序号）。本文件为**建议稿**，除 §1.5(1) 记录的决策（须另行登记到计划 §3.3）外，不改变任何既有决策；如需纳入正式流程，须同步主方案与 WBS 的引用登记。
>
> | 版本 | 日期 | 变更 |
> |---|---|---|
> | v1.0 | 2026-10-03 | 首版：iOS 基准截图逐张分析（含 2 张合规不可读确认）+ Flutter 现状差距核对 + A/B/C 前置清单 + H/I 逐页验收表 + R-6~R-8 |
> | v1.1 | 2026-10-03 | **新增两个结构性缺口专项（§1.4）**：① 首页默认内容应为豆瓣（iOS 实测为「豆瓣推荐」首页，Flutter 为纯站点驱动且无源即报错）→ 差距 D12 / 前置 A9 / 口径 R-11；② 底栏应为 5 Tab 且「福利」显隐由个人中心福利设置以 `welfareEnabled && welfareUnlocked` 双条件控制，并需 key 驱动以支持动态增删 → 差距 D13~D15 / 前置 A8 / 口径 R-9、R-10；补 §5-6~§5-9 四条风险 |
> | v1.2 | 2026-10-03 | **新增 §1.5（iOS 源码实测）**：① **全端导航形态决策** —— 全端统一底部悬浮胶囊 TabBar，TV / 桌面只自适应尺寸宽度，连带作废 07/08 样式图与计划 §3.3 的 Rail 口径；② **底栏胶囊精确规格**（基础 4 项 + 福利插入 index 3、宽度公式 `min(W−140, n×56+28)`、56/Tab、10pt、Capsule + 1px 描边、四皮肤配色、`isTabBarHidden`）；③ **「个人中心 · 福利专区」完整交互**（宫格入口 → 两阶段弹窗 → 刷新/设置入口 → 记录过滤非删除，7 条关键语义）；新增差距 D16~D18、口径 R-12/R-13、风险 §5-10/§5-11 |
> | v1.3 | 2026-10-03 | **交付回执（新增 §6）**：A8 底栏统一化（全端悬浮胶囊 + 枚举/key 驱动 + 福利 index 3 门控 + `hideTabBar`）、A9 首页豆瓣默认内容、I-01 个人中心（3×3 宫格）、H-05 福利两阶段弹窗 **四项完成并验证**（analyze 0 issue / test 全绿 / 守卫全绿 / conformance 全绿）；补 **5 Tab 态金色基线** `home_welfare_portrait`；关闭差距 D1 · D12~D18；§2.2 / §3.1 加 v1.3 状态行；注明 **D6/B1 渐变头部卡仍待办**（图10 实测为居中 Logo）；§6.4 列明 A2~A7 / B1·B3~B6 / C1~C5 / H-06·H-07 / I-02~I-05 遗留 |
> | v1.4 | 2026-10-03 | **交付回执（新增 §7）**：**A2~A7 主题层收口** —— A2 全端 `CupertinoPageTransitionsBuilder` 推入转场 · A3 `NoSplash` 去涟漪 · A4 `switchTheme` 对齐 iOS `UISwitch` 配色 · A5 `VboxScrollBehavior`（Bouncing + 抑制辉光）· A6 卡片审计（**结论：无页面级手写卡片**，2 处非卡片阴影登记观察项）· A7 `check_ui_tokens` **接入 CI**（contract-checks 10 → 11 项）**六项完成并验证**（analyze 0 issue / **test 1528 全绿** / 11/11 脚本全绿）；Story 页补**开关两态**并更新其金色基线；**A 批次 9 项全部完成**；关闭差距 **D2~D5、D7**；§2.2 / §3.1 加 v1.4 状态行；§7.4 列明 B1·B3~B6 / C1~C5 / H-06·H-07 / I-02~I-05 遗留；§7.5 登记**批次遗漏检查**（修正 CI conformance step 名的不实数字 `45 → 去写死`） |
> | v1.5 | 2026-10-03 | **交付回执（新增 §8）**：**B 批次缺失组件补齐 B3~B6** —— B3 设置分组 + 三行型（`SettingsSection` / `SettingsRow` / `SettingsInputRow`）· B4 皮肤四选 2×2（`SkinPicker` / `SkinCard`）· B5 登录弹窗（`LoginSheet`）· B6 福利分段 + 平台网格（`WelfareTabs` / `WelfarePlatformGrid`）**四项完成并验证**（analyze 0 issue / **test 1549 全绿** / 11/11 脚本全绿 / conformance 83/83）；令牌扩展（登录渐变 + 系统灰 6 / 分组底 + 福利三段渐变 + 平台 8 色板稳定哈希）；Story 页新增 B5/B6 两区块（**共 14 区**）并更新金色基线；§3.2 补 v1.3/v1.5 状态行；**B 批次 6 项中 5 项完成**，**B1 降级为不实现**（图10 实测为居中 Logo，无还原依据，随 D6 处置）；§8.4 列明 C1~C5 / H-06·H-07 / I-02~I-05 遗留 |
> | v1.6 | 2026-10-03 | **交付回执（新增 §9）**：**C1「SSIM 接入 CI」完成并验证** —— 新增 `visual-regression` job（opencv/numpy 版本固定以保证 SSIM 可复现）+ 配对清单 [visual_pairs.json](ui_baseline/visual_pairs.json)（首批 2 对）+ 脚本 `--pairs` 清单模式（含 `--update-baseline`，保留目录模式向后兼容）；**门禁口径经实测修正** —— 计划 §3.6 的绝对 SSIM ≥ 0.95 跨设备不可达（实测 首页 0.449 / 排行榜 0.254），改为「基线 − 容差」**相对门禁**（回归即红），绝对 0.95 留待 J.3 终检重定；§3.3 补 v1.6 状态行；**C 批次 1/5 完成**，C2~C5 待办（C2 随页面开发边做边接） |