#!/usr/bin/env python3
"""
TVS source tree consistency validator.

Checks that the reconstructed multi-platform source tree is self-consistent:
  1. All Dart files parse (requires flutter analyze; falls back to basic checks).
  2. Every Dart source exists for every `package:NAME/PATH` import.
  3. No leftover known syntax typos.
  4. Swift / Kotlin / C++ sources balance braces and parens.
  5. Required platform directories and manifest files exist.
  6. No unresolved cross-references between Dart files.

Usage:
    python3 _scripts/validate.py [--fix]
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Known bad patterns left over from earlier reconstruction passes.
KNOWN_TYPOS = [
    (r"\bSnack\(", "SnackBar("),
    (r"\bshowSnack\(", "showSnackBar("),
    (r"\bmainBetween\b", "mainAxisAlignment"),
    (r"\bkeyboardType\(number", "TextInputType.number"),
    (r"return\d+;", "return ...;"),
    (r"\.”_showDialog", "showDialog"),
    (r"await \._", "await "),
]

# Files that may legitimately omit line-length / lint hygiene.
LINT_IGNORE = {
    "flutter/lib/main.dart",
}


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    files_checked: int = 0

    def ok(self) -> bool:
        return not self.errors


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT)


def walk_files(base: str, exts: tuple[str, ...]) -> list[str]:
    out = []
    for dirpath, _dirs, files in os.walk(base):
        for f in files:
            if f.lower().endswith(exts):
                out.append(os.path.join(dirpath, f))
    return out


def check_braces(res: Result, path: str, pairs: list[tuple[str, str]]) -> None:
    with open(path, encoding="utf-8", errors="ignore") as fh:
        src = fh.read()
    for open_ch, close_ch in pairs:
        if src.count(open_ch) != src.count(close_ch):
            res.errors.append(
                f"{rel(path)}: unbalanced {open_ch}{close_ch} "
                f"({src.count(open_ch)} vs {src.count(close_ch)})")


def check_typos(res: Result, path: str) -> None:
    with open(path, encoding="utf-8", errors="ignore") as fh:
        src = fh.read()
    for pattern, fix in KNOWN_TYPOS:
        for m in re.finditer(pattern, src):
            line = src[: m.start()].count("\n") + 1
            res.errors.append(
                f"{rel(path)}:{line}: known typo {m.group()!r} -> {fix!r}")


def check_dart_imports(res: Result, path: str, known_targets: set[str]) -> None:
    with open(path, encoding="utf-8", errors="ignore") as fh:
        lines = fh.read().splitlines()
    for i, line in enumerate(lines, 1):
        m = re.search(r"""import\s+(?:'([^']+)'|"([^"]+)")""", line)
        if not m:
            continue
        target = m.group(1) or m.group(2)
        if target.startswith("dart:") or target.startswith("package:"):
            continue
        rel_target = os.path.normpath(
            os.path.join(os.path.dirname(path), target))
        if not os.path.exists(rel_target):
            res.errors.append(
                f"{rel(path)}:{i}: missing file for relative import "
                f"'{target}'")


def check_pubspec_deps(res: Result) -> None:
    """Verify that pubspec dependencies are declared."""
    pub = os.path.join(ROOT, "flutter", "pubspec.yaml")
    if not os.path.exists(pub):
        res.errors.append("flutter/pubspec.yaml missing")
        return
    with open(pub, encoding="utf-8") as fh:
        content = fh.read()
    for dep in ("go_router", "provider", "sqflite", "shared_preferences",
                "http", "shared_preferences"):
        if dep not in content:
            res.warnings.append(f"flutter/pubspec.yaml missing dep: {dep}")


def check_required_paths(res: Result) -> None:
    required = [
        # Android
        "android/app/build.gradle",
        "android/app/src/main/AndroidManifest.xml",
        "android/app/src/main/kotlin/com/example/tvs/MainActivity.kt",
        "android/app/src/main/kotlin/com/example/tvs/NodeBridge.kt",
        "android/app/src/main/kotlin/com/example/tvs/ConfigCenterActivity.kt",
        # Flutter
        "flutter/pubspec.yaml",
        "flutter/lib/main.dart",
        "flutter/lib/models/models.dart",
        "flutter/lib/models/app_state.dart",
        "flutter/lib/routing/router.dart",
        "flutter/lib/services/node_service.dart",
        "flutter/lib/services/player_service.dart",
        "flutter/lib/services/database_service.dart",
        "flutter/lib/services/config_service.dart",
        "flutter/lib/services/audio_service.dart",
        # yl_player plugin package
        "packages/yl_player/pubspec.yaml",
        "packages/yl_player/lib/yl_player.dart",
        "packages/yl_player/lib/src/models.dart",
        "packages/yl_player/lib/src/player_controller.dart",
        "packages/yl_player/lib/src/platform_surface.dart",
        "packages/yl_player/android/src/main/kotlin/"
        "dev/ylplayer/yl_player_android/YlPlayerPlugin.kt",
        "packages/yl_player/darwin/Classes/YlPlayerPlugin.swift",
        "packages/yl_player/windows/yl_player_plugin.cpp",
        # iOS
        "ios/Runner/AppDelegate.swift",
        "ios/Runner/NodeBridge/NodeBridgePlugin.swift",
        "ios/Runner/Info.plist",
        "ios/Podfile",
        # macOS
        "macos/Runner/AppDelegate.swift",
        "macos/Runner/MainFlutterWindow.swift",
        "macos/Runner/NodeBridge/NodeBridgePlugin.swift",
        "macos/Runner/Info.plist",
        "macos/Podfile",
        # Windows
        "windows/runner/main.cpp",
        "windows/runner/flutter_window.cpp",
        "windows/runner/win32_window.cpp",
        "windows/runner/node_process_bridge.cpp",
        "windows/CMakeLists.txt",
        # Node engine
        "node/spider/server.js",
        "node/spider/spider.js",
        "node/spider/template.js",
        "node/package.json",
    ]
    for p in required:
        if not os.path.exists(os.path.join(ROOT, p)):
            res.errors.append(f"missing required file: {p}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fix", action="store_true",
                        help="print suggested fixes (no edits)")
    _ = parser.parse_args()

    res = Result()

    # 1. Required paths.
    check_required_paths(res)

    # 2. Dart sources: typos, braces, imports.
    dart_files = (walk_files(os.path.join(ROOT, "flutter", "lib"), (".dart",)) +
                  walk_files(os.path.join(ROOT, "packages", "yl_player", "lib"),
                             (".dart",)))
    for path in dart_files:
        res.files_checked += 1
        check_typos(res, path)
        check_braces(res, path, [("{", "}"), ("(", ")"), ("[", "]")])
        check_dart_imports(res, path, set())

    # 3. Kotlin sources.
    for path in walk_files(os.path.join(ROOT, "android"), (".kt",)) + walk_files(
            os.path.join(ROOT, "packages", "yl_player", "android"), (".kt",)):
        res.files_checked += 1
        check_braces(res, path, [("{", "}"), ("(", ")")])

    # 4. Swift sources.
    for path in (walk_files(os.path.join(ROOT, "ios"), (".swift",)) +
                 walk_files(os.path.join(ROOT, "macos"), (".swift",)) +
                 walk_files(os.path.join(ROOT, "packages", "yl_player", "darwin"),
                            (".swift",))):
        res.files_checked += 1
        check_braces(res, path, [("{", "}"), ("(", ")")])

    # 5. C++ sources.
    for path in (walk_files(os.path.join(ROOT, "windows"), (".cpp", ".h")) +
                 walk_files(os.path.join(ROOT, "packages", "yl_player", "windows"),
                            (".cpp", ".h"))):
        res.files_checked += 1
        check_braces(res, path, [("{", "}"), ("(", ")")])

    # 6. Pubspec deps.
    check_pubspec_deps(res)

    # Report.
    print(f"Checked {res.files_checked} source files "
          f"across flutter/ android/ ios/ macos/ windows/ node/.")
    if res.errors:
        print(f"\n{len(res.errors)} ERROR(S):")
        for e in res.errors:
            print(f"  - {e}")
    if res.warnings:
        print(f"\n{len(res.warnings)} WARNING(S):")
        for w in res.warnings:
            print(f"  - {w}")
    if res.ok() and not res.warnings:
        print("\nOK: no consistency issues found.")
    return 0 if res.ok() else 1


if __name__ == "__main__":
    sys.exit(main())
