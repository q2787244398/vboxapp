# VBox 多端重构 · 开发进度快照

> **更新时间**：2026-09-29
> **仓库**：https://github.com/q2787244398/vboxapp （唯一开发仓库，D14）
> **唯一真相源**：`docs/DEV_PLAN_v4_with_progress.md` 的 **P 章节**（本文件为摘要，
> 细节与门禁结论以 P 章节为准）
> **事实基准**：`contract/schema/prefs_keys_v1.json`（**98 键 / 21 组 / v1.2**）

---

## 一、阶段总览

```
第 0 阶段  契约冻结        ████████████████████ 100%  ✅ 已过 D13 门禁
第 1 轮    核心骨架        ███████████░░░░░░░░░  56%  🔄 进行中（E.10b 未通过）
第 2 轮    功能补全        ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
第 3 轮    兼容性与稳定性   ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
第 4 轮    数据互通与边界   ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
第 5 轮    发布准备        ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
```

**第 1 轮 56% 的依据**：9 个交付块中完成 5 个——
✅ 契约层镜像 · ✅ 数据层 · ✅ 领域层实体 · ✅ 入口与形态判定 · ✅ conformance runner；
⬜ UI 三形态 · ⬜ 平台插件层 · ⬜ 单元测试 · ⬜ Spider 引擎实现。

---

## 二、第 0 阶段「契约冻结」✅ 已完成并推送

**门禁**：D13 六类扫描通过，老板签核 · **远程 commit**：`3b110268…`（API 逐位核验一致）

### 交付产物（15 文件）

| 类别 | 文件 | 状态 |
|------|------|------|
| SQLite DDL | `contract/schema/schema_v1.sql` | ✅ 9 表 + v1→v4 迁移链 |
| Prefs 契约 | `contract/schema/prefs_keys_v1.json` | ⚠️ 初版 53 键 → **阶段 1 修订为 98 键** |
| JSON Schema | `manifest_v1.json` / `site_v1.json` / `welfare_v1.json` | ✅ |
| Spider ABI | `contract/docs/abi_v1.md` | ✅ 引擎/操作/回调/错误全规范 |
| 备份格式 | `contract/docs/backup_v1.md` | ✅ AES-GCM + PBKDF2 字节级规范 |
| Android 兼容 | `contract/docs/android-compat.md` | ✅ minSdk 24 依据 |
| 检查模板 | `stage_check_template.yaml` / `bug_report_template.yaml` | ✅ |
| 阶段 0 报告 | `stage_check_report_stage0.yaml` | ✅ verdict: pass |
| 一致性样本 | `conformance/fixtures/`（3 类） | ✅ |

### 阶段 0 遗留缺陷（阶段 1 已修复）

| 缺陷 | 后果 | 修复 |
|------|------|------|
| v1.0 含 10 个误抓键（播放器 KVC / CA 动画 key） | 契约污染 | v1.1 移除，留档 `prefs_keys_revision_v1.1.md` |
| v1.1 仍漏 44 个真实键 | 三端偏好迁移会丢数据 | v1.2 补齐至 **98 键**，新增双向校验防回归 |

> **根因**：原提取脚本只匹配 `forKey:"k"`，漏掉 `let xKey="k"` 与 `enum XXXKeys` 两种写法；
> 原校验只验「实现↔契约」，不验「契约↔源码」。

---

## 三、第 1 轮「核心骨架」🔄 进行中

### ✅ 已完成（30 个 Dart 文件 + 工程壳）

| 模块 | 路径 | 校验 |
|------|------|------|
| 工程壳 | `pubspec.yaml`（依赖已对齐契约） | ⚠️ 缺 `android/`/`macos/`/`windows/` 平台目录 |
| 入口 | `lib/main.dart` · `lib/app.dart` | ⚠️ 未编译验证 |
| 契约镜像 | `lib/contract/schema/schema.dart` · `lib/contract/prefs_keys.dart` | ✅ 98 键 / 21 组 / 3 存储方式 |
| 数据层 | `lib/data/models/`（11）· `lib/data/datasources/local/`（3） | ✅ 往返 / 迁移链 / 加密实测通过 |
| 领域层 | `lib/domain/entities/{spider,remote_source,player}/`（10） | ✅ 引擎/容错/降级链校验通过 |
| 形态判定 | `lib/presentation/ui_mode/`（2） | ✅ 静态检查 |
| 一致性 | `conformance/runner/run_conformance.py` | ✅ **45/45 通过** |

**关键实现**
- `download` 表 v4 的 4 个可空列（`sourceType`/`engineKey`/`vodId`/`headers`）—— NULL 容忍已验证
- v2 重建表迁移（`UNIQUE(name)` → `UNIQUE(name, dyurl)`）—— 旧数据保留已验证
- 备份加密参数与 iOS `BackupManager.swift` **字节级对齐**（iter 100k / salt 16 / iv 12 / key 32 / tag 16）
- `resolveSiteMode()` 判定优先级严格复刻契约 §1.1（`isNodeSite` 覆盖 `.py` 分支）
- 表单形态判定三重判定：用户偏好 → 设备特征 → 编译期常量

### ⬜ 未完成（4 项，见 `docs/KNOWN_GAPS.md`）

| 模块 | 阻塞原因 |
|------|---------|
| UI 三形态（手机 / TV / 桌面） | 需 Flutter SDK 编译验证（G-01） |
| 平台插件层（Android Media3/VLC + 3 运行时 + 桌面 libmpv） | 需 NDK / 桌面工具链（G-02） |
| 5 个 Spider 引擎实现 | 需 QuickJS/Node/Python 运行时绑定（G-03） |
| 单元测试（目标 >70%） | 需 `flutter test`（G-05） |

---

## 四、自动化校验体系（9 个校验脚本 + 1 个 runner，全部通过）

| 脚本 | 验证内容 |
|------|---------|
| `check_contract_sync.py` | 键名 98 / 敏感键 5 / 分组 21 / 类型 98 / 误抓键防回归 / 表 9 / fixture |
| `check_contract_completeness.py` | **双向**：iOS 源码 ↔ 契约 无遗漏无冗余 |
| `check_migration_chain.py` | onCreate↔onUpgrade / 契约一致 / v4 可空列 / UNIQUE / 数据保留 |
| `check_models_roundtrip.py` | 建库 + 插入 + 读取往返 / UNIQUE / NULL 容忍 |
| `check_prefs_manager.py` | 键名在契约内 / jsonListKeys / 敏感键分派 |
| `check_backup_contract.py` | PBKDF2 实测 / AES-GCM 往返 / 错口令 / 静态检查 |
| `check_spider_domain.py` | 引擎 rawValue / 15 模式用例 / 容错解码 / 回填 / 错误检测 |
| `check_domain_remote_player.py` | 代理链 / 同步判定 / 后端降级链 / 封装回退 |
| `check_docs_consistency.py` | **文档漂移检测**：陈旧键数/组数、失效路径引用 |
| `conformance/runner/run_conformance.py` | 一致性 45 项（Spider 20 / SQLite 6 / 备份 19） |

> 另有 `check_mpv_installed_dependencies.py`（iOS CI 依赖检查，不属契约校验套件）。
> **待办**：将上述脚本接入 GitHub Actions，每次 push 自动执行。

---

## 五、iOS CI 构建状态

| 项 | 状态 |
|----|------|
| MPVKit 依赖资产缺失 | ✅ 已修复（资产迁入 vboxapp release `mpvkit-deps-0.0.1`，sha256 校验通过） |
| `scripts/*.sh` 缺执行位 | ✅ 已修复（100644 → 100755） |
| 最新构建 | ✅ run `36540984193` = success（IPA 链路跑通） |
| 版本自动 bump | ✅ 已到 `3.1614` |

---

## 六、环境约束（持续影响进度）

| 问题 | 影响 | 应对 |
|------|------|------|
| 无可用 Flutter SDK | **无法编译 / 静态分析 / 单测** | 官方 Linux 包仅 x86-64，本机 aarch64 → `Exec format error`；出路见 G-07 |
| `github.com:443` 不可达 | `git push/fetch` 失败 | 推送走 `scripts/api_push2.py`（API 通道，自动 diff） |
| 本地 git 历史与远程不一致 | 无法直接比对 | 网络恢复后 `git fetch && git reset --hard origin/main` |

> ⚠️ **所有 Dart 代码仅通过静态检查，未经编译验证**——这是当前最大风险。

---

## 七、质量门禁状态（E.10b）

```
E.10b 六类扫描：❌ 未通过（12 → 9 项不达标）
阻断：第 1 轮不得标记完成，不得进入第 2 轮
```

不达标归类：环境阻塞 3 · 功能未实现 5 · 需真机 1。
完整清单见 `docs/KNOWN_GAPS.md`（G-01 ~ G-10）。

---

## 八、决策记录（摘要）

| ID | 决策 |
|----|------|
| D1 | iOS 方案 A4：契约共享，iOS 不迁移 |
| D8 | AI 全量编码，人力只做测试 |
| D12 | TV 最低 Android 7.0（API 24） |
| D13 | 每阶段完成后必须先做遗漏检查 |
| D14 | `q2787244398/vboxapp` 唯一开发仓库 |
| D15 | 每完成阶段推送一次 |
| D16 | 源仓库 `q2787244398/app` 冻结，后续改动均在本仓库 |
| D17 | 契约键范围 = 全模块（98 键），以 iOS 源码实测为唯一基准 |
| D18 | 目录结构基准 = 方案 §2.4 五层架构 |
| D19 | 契约键须标注 `storage`（userDefaults/keychain/credentialExtra） |
| D20 | 第 1 轮当前**不可**标记完成（E.10b 未通过） |

---

## 九、下一步

| 优先级 | 事项 | 说明 |
|--------|------|------|
| **1** | 解决 Flutter 编译环境（G-07） | 建议 GitHub Actions macOS runner 跑 `flutter analyze`/`test` |
| 2 | `lib/core/*`（constants/errors/network/utils） | 纯 Dart，可静态验证 |
| 3 | `lib/domain/usecases` + `lib/data/datasources/remote` | 纯 Dart |
| 4 | 校验脚本接入 CI | 每次 push 自动执行 9 脚本 + runner |
| 5 | UI 三形态 / 平台插件层 / Spider 引擎 | **须先解决 1** |

---

*本快照由开发过程核验生成；所有「已完成」项均有对应自动化校验脚本佐证。*
*文档一致性由 `scripts/check_docs_consistency.py` 守护。*
