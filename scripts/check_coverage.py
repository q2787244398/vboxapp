#!/usr/bin/env python3
"""单测覆盖率门槛校验（第 11 个校验脚本，v6.6 新增）。

背景（P.17 #1「覆盖率口径陷阱」）
--------------------------------
`flutter test --coverage` 生成的 `coverage/lcov.info` **只包含被测试触达的文件**；
零触达文件根本不进分母。若直接读 lcov 的 `LH/LF` 汇总，会把「41/69 文件触达」
误读成 83%（实际整体远低于此），门禁 ⑤ 长期不可判。

本脚本按**全 lib 行数口径**重算整体覆盖率：
    分子 = lcov 命中行数（LH 之和）
    分母 = 已触达文件的行数（LF 之和）+ 零触达文件的**可执行行估计**

零触达文件在 lcov 里没有任何记录，故其分母用启发式「非空且非注释行数」估计——
该估计**系统性偏大**（把 class/字段/括号等非插桩行也算进去），因此算出的整体
覆盖率是**保守下界**；真实值只会更高，不会更低。

验证项：
  1. `coverage/lcov.info` 存在（否则提示先跑 `flutter test --coverage`）
  2. 整体覆盖率（全 lib 口径）≥ 门槛 70%
  3. 打印零触达文件清单（不得静默，供补测跟踪）

退出码：0 通过 / 1 不达标或缺少覆盖率数据
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
LCOV = ROOT / "coverage" / "lcov.info"

# 门禁 ⑤：整体覆盖率（全 lib 口径）≥ 70%
THRESHOLD = 70.0


def lib_files() -> list[pathlib.Path]:
    return sorted(LIB.rglob("*.dart"))


def parse_lcov(path: pathlib.Path) -> dict[str, tuple[int, int]]:
    """返回 {归一化文件路径: (LH, LF)}。"""
    recs: dict[str, tuple[int, int]] = {}
    sf: str | None = None
    lh = lf = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("SF:"):
            sf = line[3:]
        elif line.startswith("LH:"):
            lh = int(line[3:])
        elif line.startswith("LF:"):
            lf = int(line[3:])
        elif line == "end_of_record" and sf is not None:
            # SF 可能是绝对路径：归一化为相对仓库根的路径
            p = pathlib.Path(sf)
            try:
                p = p.relative_to(ROOT)
            except ValueError:
                pass
            recs[str(p)] = (lh, lf)
            sf = None
            lh = lf = 0
    return recs


def code_lines(path: pathlib.Path) -> int:
    """零触达文件的可执行行启发式估计（非空、非注释）。"""
    n = 0
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        s = raw.strip()
        if not s or s.startswith("//") or s.startswith("*") or s.startswith("/*"):
            continue
        n += 1
    return n


def main() -> int:
    print("== 单测覆盖率门槛校验（全 lib 行数口径）==")

    if not LCOV.exists():
        print(f"  ❌ 缺少 {LCOV.relative_to(ROOT)}")
        print("     请先运行：flutter test --coverage")
        return 1

    recs = parse_lcov(LCOV)
    all_files = lib_files()
    all_rel = {str(p.relative_to(ROOT)) for p in all_files}
    touched = {k: v for k, v in recs.items() if k in all_rel}
    untouched = sorted(all_rel - set(touched))

    lh = sum(v[0] for v in touched.values())
    lf_touched = sum(v[1] for v in touched.values())
    lf_untouched = sum(code_lines(ROOT / f) for f in untouched)

    denom = lf_touched + lf_untouched
    overall = 100.0 * lh / denom if denom else 0.0
    touched_pct = 100.0 * lh / lf_touched if lf_touched else 0.0

    print(f"  lib 文件：{len(all_files)} 个 · 触达 {len(touched)} · 零触达 {len(untouched)}")
    print(f"  触达口径（仅统计被触达文件）：{lh}/{lf_touched} = {touched_pct:.1f}%（口径陷阱，不作门禁）")
    print(f"  整体口径（全 lib，保守下界）：{lh}/{denom} = {overall:.1f}%（门槛 {THRESHOLD:.0f}%）")

    if untouched:
        print(f"  ⚠️  零触达文件 {len(untouched)} 个（供补测跟踪）：")
        for f in untouched:
            print(f"     - {f}")

    errors = 0
    if overall < THRESHOLD:
        print(f"  ❌ 整体覆盖率 {overall:.1f}% < 门槛 {THRESHOLD:.0f}%")
        errors += 1
    else:
        print(f"  ✅ 整体覆盖率达标（{overall:.1f}% ≥ {THRESHOLD:.0f}%）")

    print()
    if errors:
        print("覆盖率门槛校验: 失败")
        return 1
    print("覆盖率门槛校验: 通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())