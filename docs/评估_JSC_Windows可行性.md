# 评估：Windows 自建/集成 JavaScriptCore 可行性（Q-01 · 门禁）

> **任务**：WBS v1.2 §16 Q-01（批次 Q 门禁）——Windows 平台 JSC 的可用构建方案 + 体积/许可结论；**不通过 → 触发 D6 降级预案（Windows 改用 QuickJS，回老板确认）**。
> **结论先行**：✅ **可行（通过）**。推荐 **方案 A（WinCairo 官方 Windows 端口自建 JSC-only DLL + MSVC）**，方案 B（NativeScript 预编译 DLL）为加速备选；**不触发降级预案**，QuickJS 保留为运行时降级兜底（B-05 映射不变）。
> **日期**：2026-10-01 · **评估人**：开发（第 2 轮批次 B 并行）

---

## 1. 背景（为什么是门禁）

D6（主方案登记号 **D31**）已定：三端（Android / Windows / macOS）均集成 **JavaScriptCore 为 JS 站点脚本主引擎、QuickJS 为降级备份**。其中：

- **macOS**：系统自带 `JavaScriptCore.framework`，零构建成本（Q-04）；
- **Android**：JSC 预编译 `.so` 是 React Native 生态的成熟产物（四 ABI），风险低（Q-02）；
- **Windows**：Apple 已于 2012 年停止 Safari for Windows，**无官方二进制**，须自建或借第三方产物——**唯一硬骨头，故设门禁**。

## 2. 候选方案盘点

| 方案 | 路径 | 产物 | 体积（x64） | 维护方 | 可行性 |
|------|------|------|------------|--------|--------|
| **A · WinCairo 官方端口自建（推荐）** | WebKit `--jsc-only` + MSVC/CMake + WinCairoRequirements 预编译依赖 | `vbox_jsc.dll`（含 C API 导出） | ~10–18 MB | 我们（锁定 WebKit tag） | ✅ 官方支持路径，长期可控 |
| **B · NativeScript 预编译 DLL** | `@nativescript/windows-jsc`（npm，Apache-2.0 封装，自带 JSC 运行时 DLL） | 提取其 `JavaScriptCore.dll` | ~10–15 MB | NativeScript 社区 | ✅ 可用，但版本跟进受制第三方 |
| **C · MSYS2 WebKitGTK** | `javascriptcoregtk` mingw 包 | GTK 绑定式 JSC DLL + GTK 运行时 | ~25 MB+（带 GTK 依赖） | MSYS2 | ⚠️ 与 GTK 耦合过重，弃 |
| **D · 降级预案（不采用）** | Windows 仅用 QuickJS（`libvbox_quickjs` 已有 MSVC 编译管线） | 已有 | ~1 MB | 我们 | 保留为 **B-05 运行时兜底**，不作主引擎 |

**关键佐证（方案 A）**：WebKit 官方文档明确 Windows port 由官方维护——「using cairo for the graphics backend, libcurl for the network backend. It supports only 64 bit Windows」，构建工具链为最新 Visual Studio（C++ 桌面负载）+ CMake + WinCairoRequirements；`--jsc-only` 目标可跳过 WebKit 布局/渲染层，仅产出 JavaScriptCore 运行库。JSC 暴露**稳定的 C API**（`JavaScriptCore.h`：`JSGlobalContextCreate` / `JSEvaluateScript` / `JSObjectCallAsFunction` 等）——**与 iOS `QJSSpiderEngine` 用的是同一套 API**，语义对齐零成本。

## 3. 评估维度逐项结论

### 3.1 构建可行性 ✅

- 官方 Windows port 支持 `--jsc-only` 最小构建；64 位限定与产品目标一致（Windows 桌面端均为 x64）。
- 现有 `quickjs/wrapper.c` 已验证「纯 C wrapper + `dart:ffi` 动态加载」三端管线（`libvbox_quickjs`）；JSC 侧复制同一模式：`jsc/wrapper.c` 暴露 `vq_*` 风格符号（`vjq_create_runtime` / `vjq_eval` / `vjq_free_*`），Dart 侧 `jsc_ffi.dart` 镜像 `QuickJsNativeBridge` 抽象——**三端同一 ABI**（Q-05 验收口径）。
- 构建复杂度高于 QuickJS（CMake + 依赖包），但一次性投入后由 CI 固定 WebKit tag 缓存产物，不进日常开发循环。

### 3.2 体积 ✅（可接受）

| 项 | 值 | 说明 |
|----|----|------|
| `vbox_jsc.dll`（x64，MinSizeRel） | ~10–18 MB | NSIS/LZMA 压缩后安装包增量约 4–6 MB |
| 仅 x64 | 无 arm64 产物 | 官方端口 64 位限定；Windows arm64 设备占比可忽略，走 QuickJS 兜底 |
| 对照：`vbox_quickjs.dll` | ~1 MB | 已随包分发（降级备份），不因此移除 |

桌面安装包总量级（数十 MB 级）下，两位数 MB 的 DLL 增量可接受。

### 3.3 许可 ✅（合规路径明确）

- JavaScriptCore 源码：**LGPL-2.1 + BSD-2-Clause**（WebKit 双许可）。
- 合规要点：**动态链接（独立 `vbox_jsc.dll` 随安装包分发）** + 关于页（P-05）提供 WebKit 源码获取链接 + 保留版权声明。**无需开源宿主 App**。
- 对照：QuickJS 为 MIT（更宽松），方案 D 在许可上无优势差异。
- NativeScript 方案 B 的封装为 Apache-2.0，其 DLL 本身仍是 LGPL-2.1 产物，合规口径同上。

### 3.4 行为一致性 ✅

- Windows JSC 与 macOS 系统 JSC 同源同版本族（锁定同一 WebKit tag），`conformance` 双引擎双跑（B-12 / Q-06）可交叉验证。
- 与 QuickJS 的行为差集已由 **B-05a `SpiderJsGlobals` prelude**（console/print/atob/btoa/req/options）抹平——6 项能力「与引擎无关」，JSC 注入同一 prelude（Q-05 接入 `JSCBridgeEngine` 时复用）。

## 4. 对后续任务的直接影响

| 任务 | 结论 |
|------|------|
| **Q-02（Android JSC）** | 门禁通过，可启动（与 Q-03/Q-04 并行） |
| **Q-03（Windows JSC 集成）** | 按方案 A 落地：`windows/runner/jsc/` + MSVC 构建，`vbox_jsc.dll` 随 runner 打包 |
| **Q-04（macOS JSC）** | 不受影响（系统框架零构建） |
| **Q-05（JSC 引擎封装）** | `jsc_bridge_engine.dart` 复用 `QuickJsNativeBridge` 式抽象 + `SpiderJsGlobals` prelude 注入；降级开关与可观测保留 |
| **B-05（引擎映射定稿）** | **不触发降级预案**：JSC 主 / QuickJS 降级维持 D6 原案；Windows arm64（如有）自动落 QuickJS |
| **Q-06（体积/许可核销）** | 依本评估 §3.2/§3.3 登记：`vbox_jsc.dll` ~10–18 MB（x64）· LGPL-2.1 动态链接合规 |

## 5. 风险与缓解

| # | 风险 | 缓解 |
|---|------|------|
| 1 | WinCairo 构建链复杂（MSVC + CMake + 依赖包 + Cygwin 工具） | 一次性产出后 CI 缓存；锁定 WebKit tag，不追 main |
| 2 | 仅 64 位 | Windows x64 覆盖主流桌面；arm64 运行时自动降级 QuickJS（B-05 映射已含降级可观测） |
| 3 | JSC DLL 体积两位数 MB | MinSizeRel + 安装包 LZMA 压缩（增量 ~5 MB）；桌面端可接受 |
| 4 | LGPL 合规遗漏 | 关于页（P-05）加 WebKit 源码链接；Q-06 出正式核销结论 |
| 5 | 双引擎行为差异 | B-12 conformance 双跑 + B-05a prelude 已抹平能力差集 |

## 6. 参考资料

- WebKit 官方 Windows port 文档：<https://docs.webkit.org/Ports/WindowsPort.html>（MSVC / 仅 64 位 / cairo+curl）
- WebKit Building on Windows（JSC 工程与构建入口）：<https://trac.webkit.org/wiki/BuildingOnWindows>
- NativeScript Windows JSC 预编译运行时（方案 B 佐证）：<https://www.npmjs.com/package/@nativescript/windows-jsc>
- WebKitGTK JSC built products（JSC-only 独立构建产物先例）：<https://webkitgtk.org/jsc-built-products/x86_64/release/>
