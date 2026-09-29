#!/usr/bin/env python3
"""契约一致性校验：lib/contract/*.dart  vs  contract/schema/*

校验项：
  1. prefs_keys.dart 的键名集合 == prefs_keys_v1.json 的 63 键
  2. prefs_keys.dart 的敏感键集合 == JSON 的 sensitiveKeys
  3. prefs_keys.dart 的分组枚举数 == JSON 的 _group_* 分组数
  4. schema.dart 的表名集合 == schema_v1.sql 的 CREATE TABLE 表名
退出码 0 = 全通过，1 = 有不一致。
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def fail(msg: str) -> None:
    print(f"  ❌ {msg}")


def ok(msg: str) -> None:
    print(f"  ✅ {msg}")


def main() -> int:
    errors = 0

    json_path = ROOT / "contract" / "schema" / "prefs_keys_v1.json"
    dart_path = ROOT / "lib" / "contract" / "prefs_keys.dart"
    sql_path = ROOT / "contract" / "schema" / "schema_v1.sql"
    schema_dart = ROOT / "lib" / "contract" / "schema.dart"

    contract = json.loads(json_path.read_text(encoding="utf-8"))
    json_keys: set[str] = set()
    for items in contract["keys"].values():
        for it in items:
            json_keys.add(it["key"] if isinstance(it, dict) else it)
    json_sensitive = set(contract["sensitiveKeys"])
    json_groups = {g for g in contract["keys"] if g.startswith("_group_")}

    dart_text = dart_path.read_text(encoding="utf-8")
    dart_keys = set(re.findall(r"PrefsKey\(name:\s*'([^']+)'", dart_text))
    dart_sensitive = set(re.findall(r"sensitive:\s*true.*?description", dart_text) and
                         re.findall(r"name:\s*'([^']+)'[^)]*sensitive:\s*true", dart_text))
    # 更稳的敏感键提取：逐行 PrefsKey(... sensitive: true ...)
    dart_sensitive = set()
    for m in re.finditer(r"PrefsKey\(([^)]*)\)", dart_text, re.S):
        body = m.group(1)
        if "sensitive: true" in body:
            nm = re.search(r"name:\s*'([^']+)'", body)
            if nm:
                dart_sensitive.add(nm.group(1))
    dart_groups = set(re.findall(r"_group_\w+", dart_text))

    print("== 1. Prefs 键名集合 ==")
    missing = json_keys - dart_keys
    extra = dart_keys - json_keys
    if missing:
        fail(f"Dart 缺少 {len(missing)} 键: {sorted(missing)}")
        errors += 1
    if extra:
        fail(f"Dart 多出 {len(extra)} 键（契约外）: {sorted(extra)}")
        errors += 1
    if not missing and not extra:
        ok(f"键名完全一致（{len(json_keys)} 键）")

    print("== 2. 敏感键集合 ==")
    if dart_sensitive == json_sensitive:
        ok(f"敏感键一致（{len(json_sensitive)} 键）")
    else:
        fail(f"敏感键不一致 dart={sorted(dart_sensitive)} json={sorted(json_sensitive)}")
        errors += 1

    print("== 3. 分组数 ==")
    if dart_groups == json_groups:
        ok(f"分组名一致（{len(json_groups)} 组）")
    else:
        fail(f"分组不一致 缺={sorted(json_groups - dart_groups)} 多={sorted(dart_groups - json_groups)}")
        errors += 1

    # 3b. 类型一致性：Dart 的 type: PrefsType.X 必须与 JSON type 映射一致
    json_types: dict[str, str] = {}
    for items in contract["keys"].values():
        if isinstance(items, dict):
            for k_name, meta in items.items():
                if isinstance(meta, dict):
                    json_types[k_name] = meta.get("type", "")
        else:
            for it in items:
                if isinstance(it, dict):
                    json_types[it["key"]] = it.get("type", "")
    dart_types: dict[str, str] = {}
    for m in re.finditer(
        r"PrefsKey\(name:\s*'(\w+)'[^)]*?type:\s*PrefsType\.(\w+)", dart_text
    ):
        dart_types[m.group(1)] = m.group(2)
    type_map = {
        "string": "string", "stringArray": "stringArray", "bool": "bool",
        "int": "int", "long": "long", "float": "float",
    }
    type_bad = []
    for k, jt in json_types.items():
        dt = dart_types.get(k)
        if dt != type_map.get(jt):
            type_bad.append(f"{k}(json={jt} dart={dt})")
    if type_bad:
        fail(f"类型不一致: {type_bad}")
        errors += len(type_bad)
    else:
        ok(f"类型全一致（{len(json_types)} 键）")

    print("== 3c. 误抓键防回归 ==")
    false_positives = {
        "bufferedPosition", "maxBufferDuration", "highBufferDuration",
        "startBufferDuration", "maxDelayTime", "timeout", "networkTimeout",
        "positionTimerIntervalMs", "reconnect", "danmaku_scroll",
    }
    leaked = false_positives & json_keys
    if leaked:
        fail(f"误抓键回归（v1.1 应已移除）: {sorted(leaked)}")
        errors += 1
    else:
        ok("10 个误抓键（播放器 KVC / CA 动画 key）均不在契约中")

    print("== 4. SQLite 表名与字段（含迁移链）==")
    sql_text = sql_path.read_text(encoding="utf-8")
    sql_tables = set(re.findall(r"CREATE TABLE IF NOT EXISTS\s+(\w+)", sql_text))
    sd_text = schema_dart.read_text(encoding="utf-8")
    m = re.search(r"kAllTables\s*=\s*<String>\[(.*?)\]", sd_text, re.S)
    dart_tables = set(re.findall(r"'([a-z_]+)'", m.group(1))) if m else set()
    if sql_tables == dart_tables:
        ok(f"表名一致（{len(sql_tables)} 表）")
    else:
        fail(f"表名不一致 sql={sorted(sql_tables)} dart={sorted(dart_tables)}")
        errors += 1

    # 字段级：两边都跑完整迁移链后逐表比对
    import sqlite3

    sql_tabs = sqlite3.connect(":memory:")
    sql_tabs.executescript(sql_text)
    sql_cols = {}
    for (t,) in sql_tabs.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ):
        sql_cols[t] = {c[1] for c in sql_tabs.execute(f"PRAGMA table_info({t})")}

    dart_ddls = re.findall(r"'''\s*(CREATE TABLE[\s\S]*?);\s*'''", sd_text)
    dart_tabs = sqlite3.connect(":memory:")
    for ddl in dart_ddls:
        dart_tabs.executescript(ddl + ";")
    for stmt in re.findall(r"'((?:ALTER|CREATE INDEX)[^']*)'", sd_text):
        try:
            dart_tabs.executescript(stmt + ";")
        except sqlite3.Error:
            pass  # v2 重建的 RENAME 在简化链下可能冲突，字段集合不受影响
    dart_cols = {}
    for (t,) in dart_tabs.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ):
        dart_cols[t] = {c[1] for c in dart_tabs.execute(f"PRAGMA table_info({t})")}

    field_bad = 0
    for t, sc in sql_cols.items():
        dc = dart_cols.get(t, set())
        if sc != dc:
            fail(f"表 {t} 字段不一致 缺={sorted(sc - dc)} 多={sorted(dc - sc)}")
            field_bad += 1
    if field_bad == 0:
        ok(f"字段级全一致（{len(sql_cols)} 表）")
    else:
        errors += field_bad

    print("== 5. conformance fixture ==")
    fx_path = ROOT / "conformance" / "fixtures" / "sample_v4.sqlite3"
    if fx_path.exists():
        fx = sqlite3.connect(str(fx_path))
        fx_cols = {}
        for (t,) in fx.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ):
            fx_cols[t] = {c[1] for c in fx.execute(f"PRAGMA table_info({t})")}
        drift = [t for t, c in sql_cols.items() if fx_cols.get(t, set()) != c]
        if not drift and set(fx_cols) == set(sql_cols):
            ok(f"fixture 与契约一致（{len(fx_cols)} 表）")
        else:
            fail(f"fixture 漂移表: {drift}")
            errors += 1
    else:
        fail("fixture sample_v4.sqlite3 缺失")
        errors += 1

    print()
    if errors:
        print(f"校验失败：{errors} 项不一致")
        return 1
    print("校验通过：契约镜像与唯一真相源完全对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())
