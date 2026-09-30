# vbox - 多端聚合视频播放器

iOS 端：基于 Myapp3.1 (TVBox 架构) 逆向分析的 iOS 移植版本（`vbox/`，Swift / SwiftUI）。
Flutter 端：Android / Android TV / Windows / macOS 四端重构（`lib/`）。

> 本仓库为**唯一开发仓库**（iOS + Flutter 多端，决策 D14）；规划与进度见
> [`docs/VBOX_PLAN_v6.23.md`](docs/VBOX_PLAN_v6.23.md)。

## 仓库结构（顶层）

| 目录 | 说明 |
|------|------|
| `vbox/` | iOS 现有代码（Swift / SwiftUI），兼作**契约来源** |
| `lib/` | Flutter 多端共享 Dart 代码（契约 / 核心 / 数据 / 领域 已交付；表现 / 平台 待实现） |
| `android/` · `macos/` · `windows/` | Flutter 三端平台壳（v6.11 交付，`flutter create` 官方模板，包名 `com.vbox.player`） |
| `contract/` | 跨端契约层（SQLite DDL / Prefs 键 / JSON Schema / Spider ABI / 备份格式） |
| `conformance/` | 一致性样本与 runner（45 项） |
| `scripts/` | 校验（`check_*.py`）与运维脚本 |
| `go-proxy/` · `quickjs/` | 脚本运行时与代理（Spider 引擎依赖） |

## Flutter 端校验

推送后由 GitHub Actions `.github/workflows/flutter-check.yml` 执行：
契约校验脚本 + conformance runner + `flutter analyze` + `flutter test`（含覆盖率门槛）
+ 三端 `flutter build`（`build-android` / `build-macos` / `build-windows`）。

> ✅ Flutter 平台壳（`android/` `macos/` `windows/`）已于 **v6.11 交付**（D27）；
> UI 三形态（`presentation/`）与插件层（`platform/`）待实现。

## 架构

```
┌──────────────────────────────────────┐
│  SwiftUI Views                       │
│  首页 / 搜索 / 详情 / 播放器 / 设置   │
├──────────────────────────────────────┤
│  SpiderRepository (多站点聚合搜索)    │
├──────────────────────────────────────┤
│  JSSpiderEngine (JavaScriptCore)     │
│  ├─ cheerio.min.js (HTML解析)        │
│  ├─ crypto-js.js (加密)              │
│  ├─ 模板.js (TVBox站点模板)          │
│  └─ 蜘蛛脚本 (用户配置)              │
├──────────────────────────────────────┤
│  JSHTTPBridge (原生HTTP桥接)         │
│  AVPlayer (视频播放)                 │
└──────────────────────────────────────┘
```

## GitHub Actions 自动编译

每次 push 到 `main` 分支，GitHub Actions 自动编译出 `.ipa`：

1. Push 代码到 GitHub
2. 打开仓库 → Actions 页面
3. 找到最新一次运行
4. 下载 **vbox-ipa** 工件 → `vbox.ipa`
5. 用 TrollStore 打开安装

## 手动触发编译

在 GitHub Actions 页面点 **Run workflow** 按钮也可手动触发编译。

## 技术栈

- Swift 5 / SwiftUI
- JavaScriptCore (JS引擎)
- AVFoundation (视频播放)
- iOS 15.0+
- arm64 (巨魔)
TG：https://t.me/hfkj520
