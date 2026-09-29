# VBox 多端项目目录规划

> **状态**：本文档已对齐 **D18**（目录结构基准 = 方案 §2.4 五层架构）
> **唯一真相源**：`docs/DEV_PLAN_v4_with_progress.md` §2.4 —— 本文档为其落地快照
> **更新时间**：2026-09-29

`vboxapp` 仓库**同时容纳 iOS 现有代码与 Flutter 三端代码**（D14：唯一开发仓库）。

---

## 一、仓库顶层

```
vboxapp/
├── vbox/                       iOS 现有代码（Swift / SwiftUI，481 文件）
│                               └─ 契约来源；后续 iOS 改动亦在此进行（D16）
├── lib/                        Flutter 三端共享 Dart 代码
├── pubspec.yaml                Flutter 工程清单（依赖已对齐契约）
├── contract/                   契约层（唯一真相源，跨端共享）
├── conformance/                一致性样本与 runner
├── scripts/                    校验与运维脚本
├── docs/                       开发文档
├── flutter/ · quickjs/         脚本运行时源码（Spider 引擎依赖）
├── go-proxy/                   iOS 侧 Go 代理
├── remote-source-repo-template/ 远程源仓库模板
└── vbox.xcodeproj/             iOS 工程
```

> ⚠️ `android/`、`macos/`、`windows/` 平台目录**尚未创建**（见 KNOWN_GAPS G-02）。

---

## 二、`lib/` 五层架构（方案 §2.4）

```
lib/
├── main.dart                        应用入口
├── app.dart                         根组件（依赖初始化 + Provider 注入 + 形态路由）
│
├── contract/                        ── 第 1 层：契约镜像（与 contract/ 一一对应）
│   ├── prefs_keys.dart              98 键 / 21 组 / 3 种存储方式
│   ├── schema/schema.dart            9 表 DDL + v1→v4 迁移链
│   └── abi/                          Spider ABI 镜像
│
├── core/                            ── 第 2 层：通用能力
│   ├── constants/  errors/  network/  storage/  utils/
│
├── data/                            ── 第 3 层：数据
│   ├── datasources/
│   │   ├── local/                   database_manager / prefs_manager / backup_manager
│   │   └── remote/                  HTTP 数据源
│   ├── models/                      9 张表模型 + 基类 + barrel
│   └── repositories/
│
├── domain/                          ── 第 4 层：领域
│   ├── entities/
│   │   ├── spider/                  引擎类型 / 站点配置 / 结果模型 / 引擎接口 / HTTP 桥
│   │   ├── remote_source/           远程源配置与同步
│   │   └── player/                  播放器抽象 + 后端降级链
│   ├── repositories/
│   └── usecases/
│
├── presentation/                    ── 第 5 层：表现
│   ├── ui_mode/                     ⭐ 形态判定（偏好 → 设备特征 → 编译期常量）
│   ├── providers/                  状态管理
│   ├── phone/  tv/  desktop/        三套形态布局
│   ├── shared/                      跨形态复用组件
│   └── theme/
│
└── platform/                        平台插件层（各端原生实现）
    ├── player/                      Android Media3+VLC / 桌面 libmpv / iOS AVPlayer
    ├── spider/                      QuickJS / Node / NodeLX / Python / JSC 运行时绑定
    ├── runtime/
    └── system/                      文件 / 权限 / 设备能力
```

---

## 三、当前落地状态（如实标注）

| 层级 | 目录 | 状态 |
|------|------|------|
| 入口 | `main.dart` `app.dart` | ✅ 已交付（未编译验证） |
| 契约层 | `contract/` | ✅ 已交付并校验 |
| 核心层 | `core/*` | ⬜ **空目录**（5 个子目录已建） |
| 数据层 | `data/{models,datasources/local}` | ✅ 已交付 |
| 数据层 | `data/{datasources/remote,repositories}` | ⬜ 空目录 |
| 领域层 | `domain/entities/*` | ✅ 已交付 |
| 领域层 | `domain/{repositories,usecases}` | ⬜ 空目录 |
| 表现层 | `presentation/ui_mode` | ✅ 已交付 |
| 表现层 | `presentation/{phone,tv,desktop,providers,shared,theme}` | ⬜ 空目录 |
| 平台层 | `platform/*` | ⬜ **空目录**（4 个子目录已建） |
| 测试 | `test/` | ⬜ **不存在** |

> 空目录已按目标结构预建，便于后续填充；`git` 不跟踪空目录，故远端不可见。

---

## 四、约束

1. **不改 iOS 运行逻辑**（D1）：`vbox/` 仅作契约来源与参照实现
2. **契约唯一真相源**：`contract/` 与 `lib/contract/` 必须逐位对齐，
   由 `scripts/check_contract_sync.py` 守护
3. **形态判定集中于** `presentation/ui_mode/`，不得散落各布局文件
4. **平台差异隔离在** `platform/`，业务层不得直接调用原生 API
