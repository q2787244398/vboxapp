# TVS — CatVod Video Player (Reconstructed Source)

> 基于 `tvs-1.2.1` APK / IPA / dmg 逆向重建的**三端完整源码树**。
> 原版仓库：https://github.com/yuluoos/TVBox-tvs

## 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI (Dart)                        │
│  GoRouter · Provider · sqflite · audio_service · WebView    │
└──────────────┬──────────────────────────┬───────────────────┘
               │ MethodChannel            │ HTTP 127.0.0.1:9775
               ▼                          ▼
┌──────────────────────────┐   ┌──────────────────────────────┐
│   Native Bridge          │   │   Node.js Spider Engine      │
│ • Android: NodeBridge.kt │   │   node-main-template.js      │
│ • iOS:     NodeMobile.framework (in-process)                │
│ • macOS:   spawn node (child process, TVS_PARENT_PID)       │
│ • Windows: spawn node.exe (NodeProcessBridge)              │
└──────────────────────────┘   └──────────────────────────────┘
               │                          │
               ▼                          ▼
┌──────────────────────────┐   ┌──────────────────────────────┐
│   yl_player (Pigeon)     │   │   CatVod Spider Bundles      │
│ • Android: MediaCodec    │   │   search / detail / playUrl  │
│ • Apple:   AVPlayer+VT   │   │   home / hot / live          │
│ • Windows: FFmpeg (TODO) │   │   + cloud pan SDKs           │
└──────────────────────────┘   └──────────────────────────────┘
```

## 目录结构

```
tvs-rebuild/
├── flutter/                  # Dart 业务层（三端共用）
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/           # Vod, VodSite, PlaySource, AppState ...
│   │   ├── services/         # NodeService, PlayerService, ConfigService ...
│   │   ├── pages/            # Home, Search, Detail, Player, Live, Config ...
│   │   └── routing/          # GoRouter 路由表
│   ├── assets/js/            # node-main-template.js, config-center-dpad.js
│   └── pubspec.yaml
├── packages/yl_player/       # 视频播放插件（Pigeon 接口）
│   ├── lib/                  # Dart API: YlPlayerController, YlPlayerView
│   ├── android/              # Kotlin: MediaCodec + ExoPlayer
│   ├── darwin/               # Swift: AVPlayer + VideoToolbox + FFmpeg bridge
│   └── windows/              # C++: FFmpeg → TextureRegistrar (骨架)
├── android/                  # Android 原生壳
│   └── app/src/main/kotlin/com/example/tvs/
│       ├── MainActivity.kt
│       ├── NodeBridge.kt
│       ├── ConfigCenterActivity.kt
│       └── UpdateFileProvider.kt
├── ios/                      # iOS 原生壳
│   ├── Runner/
│   │   ├── AppDelegate.swift
│   │   ├── NodeBridge/NodeBridgePlugin.swift
│   │   ├── Info.plist        # UIBackgroundModes=audio, ATS allow all
│   │   └── Runner.entitlements
│   └── Podfile               # NodeMobile + YlFFmpegBridge
├── macos/                    # macOS 原生壳
│   ├── Runner/
│   │   ├── MainFlutterWindow.swift
│   │   ├── AppDelegate.swift
│   │   ├── NodeBridge/NodeBridgePlugin.swift  # spawn node 子进程
│   │   └── Info.plist
│   └── Podfile
├── windows/                  # Windows 原生壳
│   ├── runner/
│   │   ├── main.cpp
│   │   ├── flutter_window.{h,cpp}
│   │   ├── win32_window.{h,cpp}
│   │   ├── node_process_bridge.{h,cpp}
│   │   └── Runner.rc
│   └── CMakeLists.txt
├── node/                     # Node.js spider 引擎
│   ├── server.js             # 真实引导脚本（WebAssembly polyfill / AppV6 兼容 /
│   │                         #   URL 修正 / relisten / bundle switch / axios 拦截）
│   ├── routes.js             # 路由注册表（kstore 99 条 + catpaw 139 条）
│   ├── template.js           # DB 模板（14 个网盘 Provider 凭据结构）
│   ├── node-intl-polyfill.js # ICU 国际化 polyfill
│   ├── wexfnwconfig.json     # 94 站点配置（118KB）
│   ├── db.json / default.db.json
│   ├── kstore_index.js       # 编译后 bundle（6.5MB，94 站点完整版）
│   ├── catpaw_index.js       # 编译后 bundle（5.9MB，58 站点 + 弹幕）
│   └── package.json
├── node-bundle/              # 原始编译 bundle（与 node/ 同源，便于对比）
├── docs/                     # 逆向还原文档
│   ├── pan-apis.md           # 14 个网盘 API 端点与鉴权方式
│   └── callchains.md         # 五大模块调用链完整还原
├── config/tvs-config.yaml
├── _scripts/
│   ├── validate.py          # 源码一致性校验
│   └── deobfuscate.py       # 反混淆提取脚本（可复跑）
└── REVERSE_ENGINEERING_REPORT.md
```

## 构建指南

### 前置条件
- Flutter SDK ≥ 3.0（stable channel）
- Android: JDK 17, Android SDK 36, NDK
- iOS/macOS: Xcode 15+, CocoaPods
- Windows: Visual Studio 2022 (Desktop C++ workload), CMake

### Android（需先生成 Flutter 平台工程）
```bash
cd flutter
flutter pub get
# 若目标工程未由 Flutter 生成平台目录，先在 macOS/Linux 开发机执行：
# flutter create --platforms=android .
flutter build apk --release --target-platform android-arm64
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

当前 `android/` 目录保存的是逆向重建的原生壳源码与资源，依赖 Flutter Gradle 工具链生成的插件模块；它不是一个可独立运行的 Gradle 项目。

### iOS（需 macOS + Xcode）
```bash
cd flutter && flutter pub get
# 生成/刷新 iOS 工程文件（会生成完整 pbxproj、scheme、Flutter 配置）
flutter create --platforms=ios .
cd ../ios && pod install
cd .. && flutter build ipa --release
# 产物: build/ios/archive/Runner.xcarchive
# 自签分发需额外 codesign + 打包为 .ipa
```

当前 `ios/Runner.xcodeproj/project.pbxproj` 是占位说明文件；请勿直接在 Xcode 中打开构建，必须先由 `flutter create` 生成完整工程。

### macOS
```bash
cd flutter && flutter pub get
cd ../macos && pod install
cd .. && flutter build macos --release
# 产物: build/macos/Build/Products/Release/TVS.app
# 打 dmg: hdiutil create -volname TVS -srcfolder ... -ov -format UDZO tvs.dmg
```

### Windows
```powershell
cd flutter; flutter pub get
flutter build windows --release
# 产物: build\windows\x64\runner\Release\tvs.exe
# ⚠️ yl_player Windows 后端目前为骨架，播放功能需补全 FFmpeg 解码管线
```

## 构建前必须补齐的外部文件

当前 iSH 环境没有 Flutter、CocoaPods、Xcode 或 Android SDK，因此只能完成静态校验，不能在此处产出真实 APK/IPA。跨平台构建前还需：

1. 在 macOS 上于 `flutter/` 执行 `flutter pub get`，由 Flutter 生成 `ios/Flutter/`、插件注册文件和完整 `Runner.xcodeproj/project.pbxproj`；当前 pbxproj 是有意保留的占位说明，不可直接用于 Xcode 构建。
2. 提供 `../nodejs_mobile/ios` 的 NodeMobile pod，以及 `../packages/yl_player/darwin/ffmpeg_bridge` 的 YlFFmpegBridge pod。
3. 为 Android 提供 ABI 匹配的可执行 Node.js 文件：`android/app/src/main/assets/node`。仓库只放置说明文件，不放置伪造二进制。
4. 按目标平台安装对应 SDK，并在 macOS 上运行 `pod install`、在 Android 上运行 Gradle 构建。

## 已知限制 & TODO

| 项目 | 状态 | 说明 |
|------|------|------|
| Dart 业务层 | ✅ 完整 | 所有页面、服务、模型、路由已重建并通过校验 |
| Android 原生壳 | ⚠️ 源码骨架 | NodeBridge + ConfigCenter + UpdateFileProvider；需注入 ABI 匹配的 Node.js 可执行文件 |
| iOS 原生壳 | ⚠️ 源码骨架 | NodeBridgePlugin + Podfile + entitlements；需 macOS Flutter 工具链生成 pbxproj，并提供 NodeMobile/YlFFmpegBridge pods |
| macOS 原生壳 | ✅ 完整 | 子进程 Node + TVS_PARENT_PID 看门狗 |
| Windows 原生壳 | ⚠️ 可编译 | NodeProcessBridge 完整；yl_player 解码渲染待实现 |
| yl_player Android | ⚠️ 接口桩 | Pigeon 通道已注册，实际 MediaCodec 管线需接入 |
| yl_player Apple | ⚠️ 接口桩 | AVPlayer 基础实现已有，VideoToolbox 硬解需完善 |
| yl_player Windows | ❌ 骨架 | 仅通道注册，FFmpeg 解码→纹理管线未实现 |
| Isar → sqflite | ✅ 已替换 | 避免 Rust codegen 依赖，API 等价 |
| Spider bundles | ✅ 已还原 | 编译 bundle（kstore 94站 / catpaw 58站+弹幕）已纳入 |
| 网盘 Provider × 14 | ✅ API 完整 | 115/天翼/123/夸克/UC/百度/139/迅雷/B站/光鸭/蜗牛/Emby/PikPak/阿里 |
| 网盘登录流程 | ✅ 已还原 | `/website/api/login/start|poll|cancel` + 14 Provider 凭据管理 |
| Website 设置中心 | ✅ 已还原 | 站源/凭据/直播转点播/远程配置/弹幕设置 全部 API |
| Node 引导脚本 | ✅ 已还原 | WebAssembly polyfill / AppV6 兼容 / relisten / bundle switch |

## 网盘 Provider 一览

| Provider | 登录方式 | 关键 API |
|----------|----------|----------|
| 115 | Cookie 直填 | `webapi.115.com/files` |
| 天翼189 | 账号密码 | `api.cloud.189.cn/open/file/getFileDownloadUrl.action` |
| 123 | 账号密码 | `open-api.123pan.com` |
| 夸克 | Cookie 直填 | `pan.quark.cn` |
| UC | Cookie + token | `api.open.uc.cn` |
| 百度 | Cookie 直填 | `pan.baidu.com` |
| 移动139 | 手机验证码 | 伪造设备指纹 `brand=HONOR` |
| 迅雷 | 手机验证码 | `api-pan.xunlei.com` + 设备预注册指纹 |
| B站 | 扫码 | `account.bilibili.com/h5/account-h5/auth/scan-web` |
| 光鸭 | 短信 / 手动 Token | `guangyapan.com` |
| 蜗牛 woniu4k | 两步 `/login` → `/verify` | `woniu4k.com` |
| Emby | 用户自填 | 服务器地址 + 凭据 |
| PikPak | 账号密码 | `api.pikpak.com/auth/v1/login` |
| 阿里 | Token | `aliyundrive.com/adrive/v1/file/list` |

详细 API 端点、鉴权头、UA 指纹见 [docs/pan-apis.md](./docs/pan-apis.md)。

## 逆向来源

- APK: `tvs-1.2.1-x86_64.apk` (SHA256: 见 GitHub Releases)
- IPA: `TVS_Decrypted.ipa` (v1.2.1, arm64, iOS 15+)
- GitHub: https://github.com/yuluoos/TVBox-tvs/releases
- 详细分析见 [REVERSE_ENGINEERING_REPORT.md](./REVERSE_ENGINEERING_REPORT.md)

## License

本项目仅为逆向工程学习与研究用途。原始 TVS 应用版权归原作者所有。
请勿将重建代码用于任何商业或侵权用途。
