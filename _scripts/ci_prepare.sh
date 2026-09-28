#!/usr/bin/env bash
#
# CI 构建前的脚手架准备。
#
# 本仓库保存的是逆向重建的**自定义源码**（Dart 业务层、原生桥接 Kotlin/Swift、
# 资源、Node 引擎），而 Flutter 的标准平台脚手架（gradle wrapper、
# Runner.xcodeproj、xcworkspace、CMakeLists、GeneratedPluginRegistrant 等）
# 由 Flutter 工具链生成。
#
# `flutter create` 的官方行为已核实：默认 **不覆盖已存在的文件**
# （flutter_tools create.dart:88 的 --overwrite 默认 false，
#   template.dart:350-360 对已存在文件打印 "(existing - skipped)" 后 return）。
# 因此这里可以安全地调用它 —— 只补缺失文件，自定义源码原样保留。
#
# 用法: bash _scripts/ci_prepare.sh <android|ios|macos|windows> [X.Y.Z+N]
set -euo pipefail

PLATFORM="${1:?用法: ci_prepare.sh <android|ios|macos|windows> [版本]}"
VERSION="${2:-}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${HERE}/.." && pwd)/flutter"
cd "${APP_DIR}"

echo "==> 目标平台: ${PLATFORM}"
echo "==> Flutter 版本: $(flutter --version | head -n 1)"

echo "==> flutter pub get"
flutter pub get

echo "==> flutter create --platforms=${PLATFORM}（仅补缺失的脚手架）"
flutter create \
  --platforms="${PLATFORM}" \
  --org com.example \
  --project-name tvs \
  --description "TVS - CatVod video player with embedded Node.js spider engine" \
  .

if [ -n "${VERSION}" ]; then
  echo "==> 同步版本号 -> ${VERSION}"
  python3 "${HERE}/bump_version.py" --set "${VERSION}"
fi

# iOS / macOS: 自定义 Swift 桥接文件不会被 flutter create 自动加入 Xcode 工程。
# 当前阶段它们不参与编译（不影响四端构建）；接入见仓库 README。
if [ "${PLATFORM}" = "ios" ] || [ "${PLATFORM}" = "macos" ]; then
  echo "==> 提示: ${PLATFORM} 的 NodeBridgePlugin.swift 尚未接入 Xcode 工程"
fi

echo "==> 脚手架就绪: ${PLATFORM}"
