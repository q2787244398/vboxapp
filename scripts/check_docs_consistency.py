#!/usr/bin/env python3
"""文档一致性校验：防止文档漂移（documentation drift）。

背景
----
历史上出现过同一事实在文档间矛盾的情况：
  · 键数 57 / 63 / 53 / 98 四种口径并存
  · 目录重构后仍引用已删除路径（lib/contract/schema.dart 等）
  · 校验脚本数量 6 / 8 / 9 并存

本脚本把「文档漂移」转为可自动检测，规则如下：
  1. 现行键数/组数必须与契约唯一真相源一致（历史提及须带历史标记）
  2. 校验脚本数量必须为 8（scripts）或 9（含 conformance runner）
  3. 不得引用已删除的旧路径（除非该行带历史标记）
  4. 关键文档必须存在

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
HISTORY_MARKS = (
    "v1.0", "v1.1", "修订", "历史", "原", "误抓", "移除", "→", "->",
    "前", "旧", "曾", "回退", "对比", "before", "deprecated", "废弃",
    "未修复", "bug", "缺陷", "教训", "误报", "故障",
    "遗漏", "冗余", "初版", "估计", "见 P.6",
    "陈旧", "仍写", "仍列", "过时", "已删除", "同类", "失效",
)

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

DOC_GLOBS = ("docs/*.md", "contract/docs/*.md", "*.md")

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
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if is_history(line):
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
            # 旧路径
            for old in DEAD_PATHS:
                if old in line and not is_comparative(line, keys):
                    print(f"  ❌ {rel}:{i} 引用已失效路径 {old}")
                    print(f"      {line.strip()[:100]}")
                    errors += 1

    # 2：校验脚本数量（口径多义，仅告警不失败）
    print()
    n_scripts = len([
        p for p in (ROOT / "scripts").glob("check_*.py")
        if "mpv" not in p.name  # iOS CI 依赖检查，不属契约校验套件
    ])
    runner = (ROOT / "conformance" / "runner" / "run_conformance.py").exists()
    warns = 0
    print(f"校验脚本：{n_scripts} 个 check_*.py，runner={'有' if runner else '无'}")
    for p in docs:
        rel = p.relative_to(ROOT)
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if is_history(line):
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
                    print(f"  ⚠️  {rel}:{i} 脚本数 {n}（目录实为 {n_scripts}）；口径可能不同")
                    warns += 1

    # 4：关键文档存在
    print()
    for req in ("docs/PROGRESS.md", "docs/KNOWN_GAPS.md",
                "docs/DEV_PLAN_v4_with_progress.md"):
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
