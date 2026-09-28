#!/usr/bin/env python3
"""TVS 版本号自动递增 —— 单点修改，全平台同步。

设计要点
--------
Flutter 以 `flutter/pubspec.yaml` 的 `version: X.Y.Z+N` 作为**唯一版本源**，
并自动把 FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER 注入：
  * Android  (build.gradle 的 versionName / versionCode)
  * iOS      (Info.plist 的 CFBundleShortVersionString / CFBundleVersion)
  * macOS    (AppInfo.xcconfig 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION)

因此递增 pubspec.yaml 即可覆盖 Android / iOS / macOS 三大平台；本脚本额外
处理两处无法自动继承的位置：
  1. Windows 生成的 `runner/Runner.rc`（FILEVERSION / PRODUCTVERSION 为硬编码）
  2. 源码里硬编码的版本字符串（Kotlin / Swift / Dart / package.json）

用法
----
    python3 _scripts/bump_version.py --dry-run     # 只计算并打印，不写盘
    python3 _scripts/bump_version.py --apply       # 在当前基础上 +1 并写盘
    python3 _scripts/bump_version.py --set 1.2.9+14  # 精确设置（CI 矩阵用）
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "flutter" / "pubspec.yaml"
PKGJSON = ROOT / "node" / "package.json"
WIN_RC = ROOT / "flutter" / "windows" / "runner" / "Runner.rc"

PUBSPEC_RE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.M)

# 需要同步硬编码版本字符串的源码范围
SOURCE_GLOBS = [
    "flutter/lib/**/*.dart",
    "flutter/android/**/*.kt",
    "flutter/ios/**/*.swift",
    "flutter/macos/**/*.swift",
    "flutter/windows/**/*.cpp",
]


def read_current() -> tuple[str, int]:
    m = PUBSPEC_RE.search(PUBSPEC.read_text(encoding="utf-8"))
    if not m:
        sys.exit("错误：flutter/pubspec.yaml 中未找到 'version: X.Y.Z+N'")
    return m.group(1), int(m.group(2))


def parse_ver(text: str) -> tuple[str, int]:
    m = re.fullmatch(r"(\d+\.\d+\.\d+)\+(\d+)", text.strip())
    if not m:
        sys.exit(f"错误：版本格式应为 X.Y.Z+N，收到 {text!r}")
    return m.group(1), int(m.group(2))


def bump(name: str, build: int) -> tuple[str, int]:
    major, minor, patch = (int(p) for p in name.split("."))
    return f"{major}.{minor}.{patch + 1}", build + 1


def rewrite_hardcoded(old_name: str, old_build: int, new_name: str, new_build: int) -> list[str]:
    """替换源码中硬编码的旧版本字符串。返回被修改的文件列表。"""
    changed: list[str] = []
    old_variants = [f"{old_name} ({old_build})", f'"{old_name}"', f"'{old_name}'"]
    for pattern in SOURCE_GLOBS:
        for path in ROOT.glob(pattern):
            if not path.is_file():
                continue
            text = original = path.read_text(encoding="utf-8", errors="ignore")
            for old in old_variants:
                if old in text:
                    if old.startswith(f"{old_name} ("):
                        text = text.replace(old, f"{new_name} ({new_build})")
                    else:
                        text = text.replace(old, old[0] + new_name + old[-1])
            # versionCode / "versionCode": N
            text = re.sub(
                rf'("versionCode"\s*:\s*){old_build}\b', rf"\g<1>{new_build}", text
            )
            if text != original:
                path.write_text(text, encoding="utf-8")
                changed.append(str(path.relative_to(ROOT)))
    return changed


def write_windows_rc(name: str, build: int) -> bool:
    """Windows 的 Runner.rc 由 flutter create 生成，版本号是硬编码的。"""
    if not WIN_RC.is_file():
        return False
    major, minor, patch = (int(p) for p in name.split("."))
    text = WIN_RC.read_text(encoding="utf-8", errors="ignore")
    text = re.sub(
        r"(FILEVERSION\s+)\d+,\d+,\d+,\d+",
        rf"\g<1>{major},{minor},{patch},{build}",
        text,
    )
    text = re.sub(
        r"(PRODUCTVERSION\s+)\d+,\d+,\d+,\d+",
        rf"\g<1>{major},{minor},{patch},{build}",
        text,
    )
    text = re.sub(r'("FileVersion",\s*")\d+\.\d+\.\d+\.\d+(")', rf"\g<1>{name}.{build}\g<2>", text)
    text = re.sub(r'("ProductVersion",\s*")\d+\.\d+\.\d+\.\d+(")', rf"\g<1>{name}.{build}\g<2>", text)
    WIN_RC.write_text(text, encoding="utf-8")
    return True


def apply_version(old_name: str, old_build: int, new_name: str, new_build: int) -> None:
    text = PUBSPEC.read_text(encoding="utf-8")
    PUBSPEC.write_text(
        PUBSPEC_RE.sub(f"version: {new_name}+{new_build}", text, count=1),
        encoding="utf-8",
    )

    if PKGJSON.is_file():
        data = json.loads(PKGJSON.read_text(encoding="utf-8"))
        data["version"] = new_name
        PKGJSON.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    changed = rewrite_hardcoded(old_name, old_build, new_name, new_build)
    rc = write_windows_rc(new_name, new_build)

    print(f"pubspec.yaml        -> version: {new_name}+{new_build}")
    print(f"node/package.json   -> {new_name}")
    if rc:
        print(f"{WIN_RC.relative_to(ROOT)} -> {new_name}.{new_build}")
    for c in changed:
        print(f"hardcoded           -> {c}")


def main() -> int:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--dry-run", action="store_true", help="计算下一个版本并打印")
    g.add_argument("--apply", action="store_true", help="递增 +1 并写盘")
    g.add_argument("--set", metavar="X.Y.Z+N", help="设置为指定版本并写盘")
    g.add_argument("--print", action="store_true", help="只打印当前版本")
    args = ap.parse_args()

    cur_name, cur_build = read_current()

    if args.print:
        print(f"{cur_name}+{cur_build}")
        return 0

    if args.dry_run:
        new_name, new_build = bump(cur_name, cur_build)
        print(f"version={new_name}")
        print(f"build={new_build}")
        print(f"tag=v{new_name}")
        return 0

    if args.set:
        new_name, new_build = parse_ver(args.set)
    else:
        new_name, new_build = bump(cur_name, cur_build)

    apply_version(cur_name, cur_build, new_name, new_build)
    print(f"OK: {cur_name}+{cur_build} -> {new_name}+{new_build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
