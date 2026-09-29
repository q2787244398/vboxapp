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

# Node 运行时（nodejs-mobile）必须在 `flutter create` / `pod install` 之前就位：
#   android -> packages/node_bridge/android/libnode/{include,bin/<abi>/libnode.so}
#   ios     -> packages/node_bridge/ios/Frameworks/NodeMobile.xcframework
# 这两个目录体积很大（合计约 353MB），不入库，由脚本在 CI 上下载。
#
# 注意：macOS 不在其中 —— node_bridge 插件只声明了 android/ios 两个平台，
# 且 nodejs-mobile 官方未提供 macOS 产物（其 xcframework 只有 ios-arm64 与
# ios-arm64_x86_64-simulator 两个切片）。macOS 上引擎不可用，但构建照常通过。
if [ "${PLATFORM}" = "android" ] || [ "${PLATFORM}" = "ios" ]; then
  echo "==> 准备 nodejs-mobile 运行时"
  bash "${HERE}/fetch_node_runtime.sh" "${PLATFORM}" || {
    echo "!! 运行时下载失败，${PLATFORM} 将缺少 Node 引擎"
    exit 1
  }
fi

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

# iOS: CI 上没有 Apple 开发者证书。即使 flutter build 传了 --no-codesign，
# xcodebuild 仍会因为没有 Development Team 而失败
# （"Building a deployable iOS app requires a selected Development Team..."）。
# 因此必须直接在 Xcode 工程里关掉代码签名。
if [ "${PLATFORM}" = "ios" ]; then
  echo "==> 关闭 iOS 代码签名（CI 无证书）"
  if ! ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
    echo "    安装 xcodeproj gem..."
    gem install --no-document xcodeproj >/dev/null 2>&1 || true
  fi
  ruby - <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['CODE_SIGNING_ALLOWED']   = 'NO'
    config.build_settings['CODE_SIGNING_REQUIRED']  = 'NO'
    config.build_settings['CODE_SIGN_IDENTITY']     = ''
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = ''
    config.build_settings['DEVELOPMENT_TEAM']       = ''
  end
end
project.save
puts "    已关闭签名: #{project.targets.map(&:name).join(', ')}"
RUBY
fi

# iOS / macOS: 自定义 Swift 桥接文件不会被 flutter create 自动加入 Xcode 工程。
# 当前阶段它们不参与编译（不影响四端构建）；接入见仓库 README。
if [ "${PLATFORM}" = "ios" ] || [ "${PLATFORM}" = "macos" ]; then
  echo "==> 提示: ${PLATFORM} 的 NodeBridgePlugin.swift 尚未接入 Xcode 工程"
fi

echo "==> 脚手架就绪: ${PLATFORM}"
