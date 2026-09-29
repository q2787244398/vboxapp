# VBox 已知缺口登记表（Known Gaps）

> **用途**：按方案 E.10b ④「无 TODO 遗留（必须登记或清除）」要求，
> 所有未完成项必须在此登记，不得以裸 TODO 形式散落代码中。
>
> **更新**：2026-09-29 · 对应 E.10b 门禁未通过项

---

## G-01 UI 三形态未实现 ⛔ 高

| 项 | 内容 |
|----|------|
| 代码位置 | `lib/app.dart:84`（`TODO(D21/stage-1)`） |
| 影响 | 应用无法呈现实际界面，仅有占位 Scaffold |
| 阻塞原因 | 需 Flutter SDK 编译验证（见 G-07） |
| 解除条件 | `lib/presentation/{phone,tv,desktop}/` 布局交付 |
| 关联 | 方案 §2.4、T.7（TV 布局规范） |

## G-02 平台插件层未实现 ⛔ 高

| 项 | 内容 |
|----|------|
| 位置 | `lib/platform/{player,spider,runtime,system}/`（空目录）· `android/` `macos/` `windows/`（未创建） |
| 影响 | 播放器/Spider 引擎/运行时无法实际运行 |
| 阻塞原因 | 需 Android NDK + 桌面工具链 |
| 解除条件 | PlayerPlugin.kt（Media3+libVLC）、PlayerPlugin.swift、player_plugin.cpp 等交付 |
| 关联 | 方案 §2.4、D6 |

## G-03 5 个 Spider 引擎实现未开始 ⛔ 高

| 项 | 内容 |
|----|------|
| 现状 | 仅抽象层（`lib/domain/entities/spider/`），无实现 |
| 影响 | 所有 Spider 源不可用 |
| 阻塞原因 | 需 QuickJS/Node/Python 运行时绑定 |
| 解除条件 | 5 引擎（JSC/QuickJS/Node/NodeLX/Python）实现并通过 conformance |
| 关联 | 契约 `abi_v1.md`、方案 E.7 |

## G-04 conformance runner ✅ 已解决（2026-09-29）

| 项 | 内容 |
|----|------|
| 交付物 | `conformance/runner/run_conformance.py`（Python 参考实现） |
| 覆盖 | **45 项检查**：Spider ABI（20）· SQLite v4（6）· 备份格式（19） |
| 结果 | **45/45 通过**，退出码 0；结果落盘 `conformance/runner/results.json` |
| 有效性验证 | **否定测试**：注入 3 处故障（篡改容错期望值 / 删 `download.headers` 列 / 破坏表结构），runner 全部捕获并报 4 项失败 |
| 说明 | 三端（Dart/Kotlin/Swift）实现须产出与本 fixture 一致的输出；Python 版为参考实现 |

## G-04b runner 自身缺陷（已修复，记录存档）

首次运行报 3 项失败，经查**全部为 runner 自身 bug，fixture 与契约均正确**：

| # | 误报 | 真实原因 | 修复 |
|---|------|---------|------|
| 1 | `download` 字段不一致 | 契约用 `ALTER TABLE ADD COLUMN` 加 v4 列，解析器只读 `CREATE TABLE` | 补 ALTER 解析 |
| 2 | 「NOT NULL 计数为 0」断言失败 | 断言写反（变量名 `nullable` 却在收集可空列） | 改为「4 列须存在且可空」 |
| 3 | `UNIQUE(name,dyurl)` 未找到 | 内联 UNIQUE 生成**隐式索引**（`sqlite_master.sql` 为 NULL） | 改用 `PRAGMA index_list` + `index_info` |

> **教训**：查索引结构不能依赖 `sqlite_master.sql`（内联约束无 DDL 文本）；
> 契约 DDL 可能分散在 `CREATE TABLE` 与 `ALTER TABLE` 两处，须合并解析。

## G-05 单元测试为 0 ⛔ 高

| 项 | 内容 |
|----|------|
| 现状 | `test/` 目录不存在，0 个测试文件 |
| 影响 | E.10b ⑤「单测覆盖率 ≥ 70%」不达标 |
| 阻塞原因 | 需 `flutter test`（见 G-07） |
| 解除条件 | 单测交付，覆盖率 ≥ 70% |

## G-06 iOS 参照实现完整性

| 项 | 内容 |
|----|------|
| 现状 | ✅ `vbox/` 目录 481 文件完好，未被破坏 |
| 说明 | 零改造原则（D1）已遵守 |

## G-07 Flutter SDK 无法在本环境运行 ⛔ 高（根因）

| 项 | 内容 |
|----|------|
| 现象 | `Exec format error` |
| 原因 | Flutter 官方 Linux 发行版**仅 x86-64**；本机为 **aarch64**（iSH/Alpine） |
| 已查证 | `dart_sdk_arch: x64`（releases_linux.json）；arm64 归档 URL 返回 404 |
| 影响 | **阻塞 G-01/G-05/G-08 及所有编译验证** |
| 出路 | ① GitHub Actions（macos-15-arm64 runner）② x86-64 机器 ③ arm64 Linux 环境 |

## G-08 静态分析未执行

| 项 | 内容 |
|----|------|
| 现状 | `flutter analyze` 无法运行 |
| 原因 | 同 G-07 |
| 影响 | E.10b ⑤「静态分析无 error」无法验证 |

## G-09 侧载链路未验证

| 项 | 内容 |
|----|------|
| 现状 | 未验证 |
| 原因 | 需真机（人测职责，D8） |
| 关联 | 方案 §S（侧载分发）、D11 |

## G-10 TV 焦点与遥控未验证

| 项 | 内容 |
|----|------|
| 现状 | 未验证（TV UI 未实现，见 G-01） |
| 原因 | 需真机 + TV 模拟器 |
| 关联 | 方案 T.4（TV 焦点系统） |

---

## 汇总

| 类别 | 数量 | 编号 |
|------|------|------|
| ✅ 已解决 | 1 | G-04（conformance runner） |
| 环境阻塞 | 3 | G-05, G-07, G-08 |
| 功能未实现 | 4 | G-01, G-02, G-03, G-09 |
| 需真机验证 | 2 | G-09, G-10 |
| 已满足 | 1 | G-06 |

> 注：G-09 同时属「功能未实现」与「需真机验证」，故分类计数有重叠。

**E.10b 门禁状态**：❌ 未通过（不达标项 **12 → 9**，见方案文档 P.8）
