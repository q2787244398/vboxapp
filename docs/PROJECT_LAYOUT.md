# VBox 多端项目目录规划

本文档定义 `vboxapp` 仓库的目录结构，**iOS 与 Flutter 三端共存于同一仓库**（D14：唯一开发仓库）。

## 顶层结构

```
vboxapp/
├── vbox/                 iOS 现有代码（Swift / SwiftUI）
│                         └─ 契约来源 + 后续 iOS 改动亦在此
├── lib/                  Flutter 三端共享 Dart 代码（新建）
├── android/              Flutter Android 壳（新建）
├── macos/                Flutter macOS 壳（新建）
├── windows/              Flutter Windows 壳（新建）
├── contract/             契约层（机器可读，唯一真相源）
├── conformance/          一致性测试（fixtures + runner）
├── go-proxy/             Go 代理（复用 iOS 现有源码）
├── quickjs/              QuickJS 引擎（复用）
├── test/                 Dart 单测
├── docs/                 项目文档
└── .github/workflows/    CI（多端流水线）
```

## 各目录职责

| 目录 | 职责 | 状态 |
|------|------|------|
| `vbox/` | iOS 实现，**契约来源**；iOS 后续改动也在这里 | ✅ 已存在（481 文件） |
| `lib/` | Flutter 三端共享代码（UI / 领域 / 数据 / 平台抽象） | 🆕 新建 |
| `contract/` | SQLite DDL、Prefs 键名、JSON Schema、ABI/备份规范 | ✅ 阶段 0 完成 |
| `conformance/` | 跨端一致性测试样本与 runner | ✅ 阶段 0 完成 |
| `android/` | Android 手机 + TV 双形态壳（同一 APK） | 🆕 新建 |
| `macos/` | macOS 壳（libmpv 播放） | 🆕 新建 |
| `windows/` | Windows 壳（libmpv 播放） | 🆕 新建 |
| `go-proxy/` | Go 代理（三级降级链：ghfast.top → gh-proxy.com → 直连） | ✅ 复用 |
| `quickjs/` | QuickJS 引擎源码（Flutter 经 FFI 调用） | ✅ 复用 |
| `test/` | Dart 单元测试（覆盖率目标 ≥ 70%） | 🆕 新建 |

## `lib/` 内部分层

```
lib/
├── main.dart                    应用入口（平台分流）
├── contract/                    ★ 契约层（严格对齐 contract/）
│   ├── schema.dart              SQLite DDL 常量 + 迁移链
│   ├── prefs_keys.dart          Prefs 键名常量 + 敏感键标记
│   └── validators.dart          JSON Schema 校验
├── data/                        数据层
│   ├── models/                  9 张表对应的 Dart 模型
│   │   ├── zhanyuan.dart        自建源
│   │   ├── apiyuan.dart         API 源
│   │   ├── subscription.dart    订阅
│   │   ├── favorite.dart        收藏
│   │   ├── history.dart         历史
│   │   ├── download.dart        下载
│   │   ├── settings.dart        设置
│   │   ├── jiexisetting.dart    解析设置
│   │   └── search_history.dart  搜索历史
│   ├── database_manager.dart    建表 / 迁移 / CRUD
│   ├── prefs_manager.dart       偏好读写
│   └── backup_manager.dart      备份加解密（AES-GCM + PBKDF2）
├── domain/                      领域层
│   ├── spider/                  Spider 引擎抽象
│   │   ├── engine_type.dart     5 引擎枚举
│   │   ├── spider_engine.dart   5 操作协议
│   │   └── spider_models.dart   SiteConfig / 各 Result 模型
│   ├── remote_source/           远程源配置
│   └── player/                  播放器抽象（Android: Media3/VLC；桌面: libmpv）
└── ui/                          UI 层
    ├── phone/                   手机布局
    ├── tv/                      TV 布局（焦点导航）
    └── desktop/                 桌面布局
```

## Flutter 与 iOS 工程隔离

⚠️ **重要**：现有 `vbox.xcodeproj` + `Podfile` 是 **iOS 原生工程**配置。

| 风险 | 处理 |
|------|------|
| Flutter 的 `ios/` 目录与现有 `vbox/` 冲突 | **不生成 Flutter 的 `ios/` 目录**（iOS 保留原生 SwiftUI，D1） |
| `pubspec.yaml` 与 `Podfile` 互不干扰 | ✅ 独立文件，无冲突 |
| CI 需要区分 iOS / Flutter 两条流水线 | 见 `.github/workflows/` |

**结论**：Flutter 仅负责 Android / Android TV / Windows / macOS 四端；iOS 维持原生实现，通过**契约层**保证数据互通（D7）。

## 平台与最低版本

| 平台 | 最低版本 | 依据 |
|------|---------|------|
| Android 手机 | API 24 (7.0) | D12 |
| Android TV | API 24 (7.0) | D12 |
| Windows | 10 (1809+) | Flutter 官方支持 |
| macOS | 10.15+ | Flutter 官方支持 |
| iOS | 现有（不改造） | D1 |
