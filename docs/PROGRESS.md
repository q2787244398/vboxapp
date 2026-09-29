# VBox 多端重构 · 开发进度报告

> **生成时间**：2026-09-29
> **仓库**：https://github.com/q2787244398/vboxapp （唯一开发仓库，D14）
> **远程 HEAD**：`ce1859e2` · 465 个文件
> **当前阶段**：**第 1 轮迭代「核心骨架」进行中**
> **依据文档**：`vbox_flutter_migration_plan.md`（v4 定稿）· `docs/PROJECT_LAYOUT.md`

---

## 一、总体进度总览

```
第 0 阶段  契约冻结        ████████████████████ 100%  ✅ 已完成并通过门禁
第 1 轮    核心骨架        ██████████░░░░░░░░░░  50%  🔄 进行中
第 2 轮    功能补全        ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
第 3 轮    兼容性与稳定性   ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
第 4 轮    数据互通与边界   ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
第 5 轮    发布准备        ░░░░░░░░░░░░░░░░░░░░   0%  ⬜ 未开始
```

---

## 二、第 0 阶段「契约冻结」—— ✅ 已完成

**状态**：已通过 D13 质量门禁（六类扫描全 pass），老板签核批准
**Commit**：`3b11026`（本地）/ 已推送

### 交付产物（14 项）

| 类别 | 文件 | 状态 |
|------|------|------|
| SQLite DDL | `contract/schema/schema_v1.sql` | ✅ 9 表 + v1→v4 迁移链 |
| Prefs 契约 | `contract/schema/prefs_keys_v1.json` | ✅ **v1.1，53 键 / 12 组** |
| JSON Schema | `manifest_v1.json` / `site_v1.json` / `welfare_v1.json` | ✅ |
| Spider ABI | `contract/docs/abi_v1.md` | ✅ 引擎/操作/回调/错误全规范 |
| 备份格式 | `contract/docs/backup_v1.md` | ✅ AES-GCM + PBKDF2 字节级规范 |
| Android 兼容 | `contract/docs/android-compat.md` | ✅ minSdk 24 依据 |
| 阶段检查模板 | `stage_check_template.yaml` / `bug_report_template.yaml` | ✅ |
| 阶段 0 报告 | `stage_check_report_stage0.yaml` | ✅ verdict: pass |
| Spider 样本 | `conformance/fixtures/spider_io_v1.json` | ✅ |
| 数据库样本 | `conformance/fixtures/sample_v4.sqlite3` | ✅ 9 表建库通过 |
| 备份样本 | `conformance/fixtures/backup_v1.json` | ✅ |

### ⚠️ 本阶段发现并修复的契约缺陷（D13 流程）

**问题**：`prefs_keys_v1.json` v1.0 的 63 键中，**10 个是误抓**——
它们是 AliPlayer/IJKPlayer 的 **KVC 属性名**与 **CoreAnimation 动画 key**，
并非 UserDefaults 偏好键。

**根因**：提取脚本只匹配 `forKey:`，未区分调用主体：
```swift
UserDefaults.standard.set(v, forKey: "player_auto_play_next")  // ✅ 真 prefs 键
obj.value(forKey: "bufferedPosition")                          // ❌ 播放器 KVC 属性
```

**修订结果**：63 键 → **53 键**（`_group_buffer` 整组移除 + 3 个散键）
**留档**：`contract/docs/prefs_keys_revision_v1.1.md`（逐键源码行号证据）
**防回归**：`check_contract_sync.py` 已加断言，10 个误抓键不得再出现

---

## 三、第 1 轮迭代「核心骨架」—— 🔄 进行中（约 50%）

### ✅ 已完成部分

#### 3.1 契约层 Dart 镜像

| 文件 | 内容 | 校验 |
|------|------|------|
| `lib/contract/schema.dart` | 9 表 DDL + v1→v4 迁移链 + `kSchemaVersion=4` | ✅ 字段级 9/9 一致 |
| `lib/contract/prefs_keys.dart` | 53 键 / 12 组 / 5 敏感键（含 type + default） | ✅ 类型 53/53 一致 |

#### 3.2 数据层（`lib/data/`）

| 文件 | 内容 | 校验 |
|------|------|------|
| `models/`（10 文件） | 9 张表模型 + 基类 + barrel | ✅ 9/9 字段一致 |
| `database_manager.dart` | 建库/迁移链/CRUD + 类型安全便捷方法 | ✅ 双路径（onCreate/onUpgrade）一致 |
| `prefs_manager.dart` | 53 键读写 + 5 敏感键走 secure storage | ✅ 4 项检查通过 |
| `backup_manager.dart` | AES-256-GCM + PBKDF2（100k/16/12/32/16） | ✅ 5 组验证通过 |

**关键实现**：
- `download` 表 v4 的 4 个可空列（`sourceType`/`engineKey`/`vodId`/`headers`）—— NULL 容忍已验证
- v2 重建表迁移（`UNIQUE(name)` → `UNIQUE(name, dyurl)`）—— 旧数据保留已验证
- 备份加密参数与 iOS `BackupManager.swift` **字节级对齐**（含 `cipher`/`kdf` 字面值）

#### 3.3 领域层 Spider（`lib/domain/spider/`）

| 文件 | 内容 |
|------|------|
| `engine_type.dart` | `SpiderEngineType`（5 引擎）+ `SiteMode`（6 模式） |
| `site_config.dart` | `SiteConfig`（19 字段）+ `isNodeSite` + `resolveSiteMode()` |
| `spider_models.dart` | 5 结果类型 + **容错解码** + `urls` 回填 |
| `spider_engine.dart` | 抽象接口（5 生命周期 + 5 操作）+ 7 错误码 |
| `http_bridge.dart` | HTTP 参数 + **5 级编码探测链** + charset 映射表 |

**关键实现**：
- 判定优先级严格复刻契约 §1.1（① `isNodeSite` 覆盖 ④ `.py`，已核实契约原文）
- 容错解码：`vod_id`/`vod_name`/`vod_pic`/`type_id`/`type_name` 支持 String/Int/Double
- 编码探测：Content-Type charset → UTF-8 → meta 探测 → GBK/Big5/Latin1 → base64

### ⬜ 第 1 轮剩余部分

| 模块 | 状态 | 阻塞原因 |
|------|------|---------|
| 平台插件层（Android Media3/VLC + 3 运行时 + Go） | ⬜ 未开始 | **需 Flutter SDK + Android NDK** |
| 平台插件层（Windows/macOS libmpv） | ⬜ 未开始 | **需 Flutter SDK + 桌面工具链** |
| UI 三形态（手机/TV/桌面） | ⬜ 未开始 | 需 Flutter SDK 才能编译验证 |
| 远程源管理（`lib/domain/remote_source/`） | ⬜ 未开始 | 纯 Dart，**可立即继续** |
| 单测 + conformance runner | ⬜ 未开始 | 需 Flutter SDK（`flutter test`） |

---

## 四、自动化校验体系（6 个脚本，全部通过）

| 脚本 | 验证内容 | 结果 |
|------|---------|------|
| `check_contract_sync.py` | 键名53/敏感键5/分组12/类型53/防回归/表9/fixture | ✅ |
| `check_migration_chain.py` | onCreate↔onUpgrade 一致、契约一致、v4 可空列、UNIQUE、旧数据保留 | ✅ |
| `check_models_roundtrip.py` | 建库+插入+读取往返、UNIQUE 约束、NULL 容忍 | ✅ |
| `check_prefs_manager.py` | 键名在契约内、jsonListKeys 子集、敏感键走 secure | ✅ |
| `check_backup_contract.py` | 参数实测、文档核对、AES-GCM 往返、错口令、静态检查 | ✅ |
| `check_spider_domain.py` | 引擎 rawValue、15 模式解析用例、容错解码、回填、错误检测 | ✅ |

> 建议：将上述脚本接入 CI（`.github/workflows/`），每次 push 自动执行。

---

## 五、iOS CI 构建状态

| 问题 | 状态 |
|------|------|
| MPVKit 依赖资产缺失 | ✅ **已修复**（资产从原仓库 `app` 迁入 vboxapp release） |
| `scripts/*.sh` 缺执行位 | ✅ **已修复**（100644 → 100755） |
| **最新构建结果** | ✅ **run 36540984193 = success**（IPA 构建链路全线跑通） |
| 版本自动 bump | ✅ 已到 `3.1614` |

---

## 六、当前环境问题（需注意）

| 问题 | 影响 | 应对 |
|------|------|------|
| `github.com:443` 不可达 | `git push/fetch` 失败 | 推送走 `scripts/api_push2.py`（API 通道，支持自动 diff） |
| 本地 git 历史与远程不一致 | 无法直接 `git status` 比对 | 网络恢复后 `git fetch && git reset --hard origin/main` |
| 无 Flutter SDK | 无法编译/单测 | 插件层与 UI 层受阻 |

---

## 七、下一步计划

### 立即可做（无需 Flutter SDK）
1. `lib/domain/remote_source/` — 远程源配置管理（纯 Dart）
2. `lib/domain/player/` — 播放器抽象接口（纯 Dart）
3. 把 6 个校验脚本接入 CI workflow

### 需要环境支持
4. 搭建 Flutter SDK（iSH aarch64 可行性待验证）
5. 平台插件层实现
6. UI 三形态 + 单测

---

## 八、决策记录回顾（关键 6 条）

| ID | 决策 | 状态 |
|----|------|------|
| D1 | iOS 方案 A4：契约共享，iOS 不迁移 | ✅ 执行中 |
| D8 | AI 全量编码，人力只做测试 | ✅ 执行中 |
| D12 | TV 最低 Android 7.0（API 24） | ✅ 已定 |
| D13 | 每阶段完成后必须先做遗漏检查 | ✅ 已应用（契约修订走此流程） |
| D14 | `q2787244398/vboxapp` 唯一开发仓库 | ✅ |
| D15 | 每完成阶段推送一次 | ✅ 已推送多次 |

---

*本报告由开发过程自动核验生成，所有「已完成」项均有对应的自动化校验脚本佐证。*
