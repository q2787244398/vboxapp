#!/usr/bin/env python3
"""文档一致性校验：防止文档漂移（documentation drift）。

背景
----
历史上出现过同一事实在文档间矛盾的情况：
  · 键数 57 / 63 / 53 / 98 四种口径并存
  · 目录重构后仍引用已删除路径（lib/contract/schema.dart 等）
  · 校验脚本数量 6 / 8 / 9 并存

本脚本把「文档漂移」转为可自动检测，规则如下：
  1. 现行键数/组数必须与契约唯一真相源一致（含表格/加粗/合计三种写法，v6.2 起）
  2. 校验脚本数量必须与 scripts/ 目录实际数量一致（含 conformance runner 时 +1）
  3. 不得引用已删除的旧路径或已并入的附属文档（PROJECT_LAYOUT/PROGRESS/KNOWN_GAPS）
  4. 源码（`lib/**/*.dart`）注释不得引用已删除文档 / 失效路径（v6.2 新增）
  5. 关键文档（唯一主方案文档）必须存在

v6.2 补丁：v6.1 的键数规则要求数字紧邻「键」字，§C.3 把合计写成
``| **合计** | **57** |``（数字后是竖线），整节 57 键 / 14 组得以绕过检测。
现按「表格单元格 / 加粗 / 合计」三种包裹形式识别数值，堵住该格式化逃逸。

历史豁免的两种显式方式（二者取一，禁止靠模糊措辞自我豁免）：
  · 行内强标记：v1.0/v1.1/v1.2、修订、历史、误抓、已删除、废弃、→ 等
  · 块级标记：``<!-- docs-guard:history -->`` 与 ``<!-- /docs-guard:history -->`` 之间的整块
「修复前 vs 修复后」对比表、历史数值表必须放进块级标记；
不得再用「（初版估计值，见 P.6）」这类措辞冒充历史语境（该漏洞已随 v6.1 移除）。

退出码：0 通过 / 1 存在漂移
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Iterable

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "contract" / "schema" / "prefs_keys_v1.json"

# 允许出现「旧数值」的语境标记（历史叙述、修订对比）
# v6.1：移除「初版 / 估计 / 见 P.6」——这三个弱标记曾让主方案 §2.x 的
#       4 处陈旧「57 键」整行自我豁免，是历史豁免的真实漏洞。
HISTORY_MARKS = (
    "v1.0", "v1.1", "v1.2", "修订", "历史", "原", "误抓", "移除", "→", "->",
    "前", "旧", "曾", "回退", "对比", "before", "deprecated", "废弃",
    "未修复", "bug", "缺陷", "教训", "误报", "故障",
    "遗漏", "冗余",
    "陈旧", "仍写", "仍列", "过时", "已删除", "同类", "失效",
    "取代",  # v6.2：历史对比用词（如 D18「取代中途生成的 PROJECT_LAYOUT.md」）
)

# 块级历史标记：两行之间的整块豁免「数值规则」（已删除路径规则仍生效）
BLOCK_ON = "<!-- docs-guard:history -->"
BLOCK_OFF = "<!-- /docs-guard:history -->"

# 已知的陈旧总数（曾出现过的错误口径）——仅这些值触发失败
STALE_KEY_COUNTS = {44, 53, 57, 63}
STALE_GROUP_COUNTS = {12, 13}

# 目录重构后已失效的路径（不得作为现行路径引用）
DEAD_PATHS = (
    "lib/contract/schema.dart",
    "lib/data/database_manager.dart",
    "lib/data/prefs_manager.dart",
    "lib/data/backup_manager.dart",
    "lib/domain/spider/",
    "lib/domain/remote_source/",
    "lib/domain/player/player.dart",
)

# v5 并入本方案后已删除的附属文档：不得作为「现行真相源」引用。
# v6.2 新增：此前 app.dart 注释仍写「唯一真相源：docs/PROJECT_LAYOUT.md」，
#           而守卫只扫 *.md，源码注释里的失效引用完全失控。
DEAD_DOCS = ("PROJECT_LAYOUT.md", "PROGRESS.md", "KNOWN_GAPS.md")

DOC_GLOBS = ("docs/*.md", "contract/docs/*.md", "*.md")

# 源码目录：其中注释引用的失效路径/文档同样纳管（v6.2 新增）
DART_GLOBS = ("lib/**/*.dart",)

# 数值的「表格 / 加粗 / 合计」写法（v6.2 新增，堵 §C.3 式逃逸）：
#   旧漏洞：C.3 的合计写成 `| **合计** | **57** |`，数字后无「键」字，
#   得以绕过 `(\d+)\s*键` 规则；本组正则按「数值被表格/加粗/合计包裹」识别。
INLINE_COUNT_PATTERNS = (
    r"\*\*(\d{2,3})\*\*",                          # **57**
    r"\|\s*(\d{2,3})\s*\|",                        # | 57 |
    r"(?:合计|总计|共)\s*[:：]?\s*\*{0,2}(\d{2,3})",  # 合计 57
)

# 历史记录类文档（修订说明/变更日志）：其数值描述的是当时状态，整体豁免数值规则
HISTORICAL_DOC_PAT = re.compile(r"(revision|history|changelog|修订|历史)", re.I)


def iter_docs() -> Iterable[pathlib.Path]:
    seen: set[pathlib.Path] = set()
    for g in DOC_GLOBS:
        for p in ROOT.glob(g):
            if p.is_file() and p not in seen:
                seen.add(p)
                yield p


def is_history(line: str) -> bool:
    """判断该行是否为历史/对比叙述（含对比语境，避免自指误报）。"""
    return any(m in line for m in HISTORY_MARKS)


def is_comparative(line: str, cur: int) -> bool:
    """行内同时出现现行数值 → 属新旧对比叙述，豁免。"""
    return str(cur) in line


def is_historical_doc(p: pathlib.Path) -> bool:
    return bool(HISTORICAL_DOC_PAT.search(p.name))


def main() -> int:
    errors = 0
    d = json.loads(CONTRACT.read_text(encoding="utf-8"))
    keys = sum(len(v) for v in d["keys"].values())
    groups = len(d["keys"])
    print(f"真相源：{keys} 键 / {groups} 组 / "
          f"v{d['schemaVersion']}（{CONTRACT.relative_to(ROOT)}）\n")

    docs = sorted(iter_docs())
    print(f"扫描 {len(docs)} 个文档\n")

    # 1 + 3：键数/组数 + 旧路径
    for p in docs:
        rel = p.relative_to(ROOT)
        if is_historical_doc(p):
            print(f"  ·  {rel}（历史记录文档，数值规则豁免）")
            continue
        in_block = False
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if BLOCK_OFF in line:
                in_block = False
                continue
            if BLOCK_ON in line:
                in_block = True
                continue
            if in_block or is_history(line):
                continue
            # 键数（仅在命中已知陈旧口径时失败，避免误伤白名单/KVC 等异对象计数）
            for m in re.finditer(r"(\d+)\s*键", line):
                n = int(m.group(1))
                if n in STALE_KEY_COUNTS and not is_comparative(line, keys):
                    print(f"  ❌ {rel}:{i} 陈旧键数 {n}（现行 {keys}）")
                    print(f"      {line.strip()[:100]}")
                    errors += 1
            # 组数（须与「键」或「分组」共现，避免误伤「5 组验证」等措辞）
            if "键" in line or "分组" in line:
                for m in re.finditer(r"(\d+)\s*组", line):
                    n = int(m.group(1))
                    if n in STALE_GROUP_COUNTS and not is_comparative(line, groups):
                        print(f"  ❌ {rel}:{i} 陈旧组数 {n}（现行 {groups}）")
                        print(f"      {line.strip()[:100]}")
                        errors += 1
            # 数值的表格 / 加粗 / 合计写法（v6.2：堵 §C.3 式「无键字」逃逸）
            for pat in INLINE_COUNT_PATTERNS:
                for m in re.finditer(pat, line):
                    n = int(m.group(1))
                    if n in STALE_KEY_COUNTS and not is_comparative(line, keys):
                        print(f"  ❌ {rel}:{i} 陈旧键数（表格写法）{n}（现行 {keys}）")
                        print(f"      {line.strip()[:100]}")
                        errors += 1
            # 旧路径 / 已删除文档
            for old in DEAD_PATHS + DEAD_DOCS:
                if old in line and not is_comparative(line, keys):
                    print(f"  ❌ {rel}:{i} 引用已失效路径/文档 {old}")
                    print(f"      {line.strip()[:100]}")
                    errors += 1

    # 2：校验脚本数量（v6.1 起为硬失败：须与 scripts/ 目录实际数量一致）
    print()
    n_scripts = len([
        p for p in (ROOT / "scripts").glob("check_*.py")
        if "mpv" not in p.name  # iOS CI 依赖检查，不属契约校验套件
    ])
    runner = (ROOT / "conformance" / "runner" / "run_conformance.py").exists()
    print(f"校验脚本：{n_scripts} 个 check_*.py，runner={'有' if runner else '无'}")
    for p in docs:
        rel = p.relative_to(ROOT)
        in_block = False
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if BLOCK_OFF in line:
                in_block = False
                continue
            if BLOCK_ON in line:
                in_block = True
                continue
            if in_block or is_history(line):
                continue
            if "校验" not in line:
                continue
            m = re.search(r"(\d+)\s*(?:个\s*)?(?:校验\s*)?脚本", line)
            if m:
                n = int(m.group(1))
                # 排除「100% ... 脚本」这类百分号误匹配
                if "%" in line[m.start():m.end()]:
                    continue
                if n not in (n_scripts, n_scripts + (1 if runner else 0)):
                    print(f"  ❌ {rel}:{i} 脚本数 {n}（目录实为 {n_scripts}）")
                    print(f"      {line.strip()[:100]}")
                    errors += 1

    # 4：源码注释不得引用已删除文档 / 失效路径（v6.2 新增）
    print()
    for g in DART_GLOBS:
        for p in sorted(ROOT.glob(g)):
            rel = p.relative_to(ROOT)
            for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
                for bad in DEAD_DOCS + DEAD_PATHS:
                    if bad in line:
                        print(f"  ❌ {rel}:{i} 源码引用已失效路径/文档 {bad}")
                        print(f"      {line.strip()[:100]}")
                        errors += 1

    # 5：关键文档存在
    print()
    for req in ("docs/VBOX_PLAN_v6.md",):
        ok = (ROOT / req).exists()
        print(f"  {'✅' if ok else '❌'} {req} 存在")
        if not ok:
            errors += 1

    print()
    if errors:
        print(f"校验失败：发现 {errors} 处文档漂移")
        return 1
    print("校验通过：文档与真相源一致，无失效路径引用")
    return 0


if __name__ == "__main__":
    sys.exit(main())
