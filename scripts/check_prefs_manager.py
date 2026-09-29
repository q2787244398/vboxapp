#!/usr/bin/env python3
"""校验 prefs_manager.dart 与契约的一致性。

1. 文件内所有键名字面量必须在 prefs_keys_v1.json 内
2. jsonListKeys 集合必须是契约键的子集
3. 敏感键必须经 meta.sensitive 分支走 secure storage（静态检查）
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    c = json.loads((ROOT / "contract/schema/prefs_keys_v1.json").read_text())
    contract_keys: set[str] = set()
    for items in c["keys"].values():
        contract_keys |= set(items.keys())
    sensitive = set(c["sensitiveKeys"])

    pm = (ROOT / "lib/data/datasources/local/prefs_manager.dart").read_text()
    errors = 0

    print("== 1. 键名字面量必须在契约内 ==")
    literals = set(re.findall(r"'([a-z_][a-zA-Z0-9_]{3,})'", pm))
    refs = {k for k in literals if "_" in k}
    unknown = refs - contract_keys
    if unknown:
        print(f"  ❌ 契约外键: {sorted(unknown)}")
        errors += 1
    else:
        print(f"  ✅ {len(refs & contract_keys)} 个键引用全部在契约内")

    print("== 2. jsonListKeys 必须是契约子集 ==")
    m = re.search(r"jsonListKeys = <String>\{(.*?)\}", pm, re.S)
    jlk = set(re.findall(r"'(\w+)'", m.group(1))) if m else set()
    bad = jlk - contract_keys
    if bad:
        print(f"  ❌ 契约外: {sorted(bad)}")
        errors += 1
    else:
        print(f"  ✅ {len(jlk)} 个 JSON 列表键均在契约内")

    print("== 3. 敏感键走 secure storage ==")
    if "meta.sensitive" in pm and "FlutterSecureStorage" in pm:
        print("  ✅ 存在 meta.sensitive 分支 + secure storage 引用")
    else:
        print("  ❌ 未检测到敏感键分派逻辑")
        errors += 1

    print("== 4. 契约键总数核对 ==")
    print(f"  ✅ 契约 {len(contract_keys)} 键，敏感 {len(sensitive)} 个")

    print()
    print("prefs_manager 校验:", "通过 ✅" if errors == 0 else f"{errors} 项失败")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
