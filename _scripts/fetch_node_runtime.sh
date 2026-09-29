#!/usr/bin/env bash
#
# 下载 nodejs-mobile 运行时到 packages/node_bridge/ 下的对应目录。
#
# 为什么不在仓库里直接存放：
#   - Android 三个 ABI 的 libnode.so 合计约 186 MB
#   - iOS NodeMobile.xcframework device 切片 52 MB + simulator 切片 115 MB
# 这些都不适合进 git，因此由 CI 在构建前拉取。
#
# 产物位置（均已在 .gitignore 中忽略）：
#   Android -> packages/node_bridge/android/libnode/{include,bin/<abi>/libnode.so}
#   iOS     -> packages/node_bridge/ios/Frameworks/NodeMobile.xcframework
#
# 用法: bash _scripts/fetch_node_runtime.sh <android|ios>
#        bash _scripts/fetch_node_runtime.sh android /path/to/local.zip   # 本地缓存包
set -euo pipefail

PLATFORM="${1:?用法: fetch_node_runtime.sh <android|ios> [本地zip路径]}"
LOCAL_ZIP="${2:-}"

NODEJS_MOBILE_VERSION="18.20.4"
# 与原版 App 内 libnode.so 的 Node 版本一致（实测为 v18.20.4）
BASE_URL="https://github.com/nodejs-mobile/nodejs-mobile/releases/download/v${NODEJS_MOBILE_VERSION}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${HERE}/../packages/node_bridge" && pwd)"

download() {
  local url="$1" dest="$2"
  if [ -n "${LOCAL_ZIP}" ] && [ -f "${LOCAL_ZIP}" ]; then
    echo "    使用本地缓存: ${LOCAL_ZIP}"
    cp "${LOCAL_ZIP}" "${dest}"
    return
  fi
  echo "    下载: ${url}"
  curl -fSL --retry 3 --retry-delay 5 --max-time 900 -o "${dest}" "${url}"
}

case "${PLATFORM}" in
  android)
    TARGET="${PLUGIN_DIR}/android/libnode"
    if [ -f "${TARGET}/bin/arm64-v8a/libnode.so" ]; then
      echo "==> Android 运行时已存在，跳过下载"
      exit 0
    fi
    echo "==> 准备 Android nodejs-mobile 运行时 (v${NODEJS_MOBILE_VERSION})"
    TMP="$(mktemp -d)"
    trap 'rm -rf "${TMP}"' EXIT
    download "${BASE_URL}/nodejs-mobile-v${NODEJS_MOBILE_VERSION}-android.zip" "${TMP}/nm.zip"
    rm -rf "${TARGET}"
    mkdir -p "${TARGET}"
    # 只取 include/ 与 bin/，其余（如 node 可执行文件）不需要
    ( cd "${TMP}" && unzip -q nm.zip 'include/*' 'bin/*' -d "${TARGET}" )
    echo "    -> ${TARGET}"
    ls -1 "${TARGET}/bin" | sed 's/^/       ABI: /'
    ;;

  ios)
    TARGET="${PLUGIN_DIR}/ios/Frameworks/NodeMobile.xcframework"
    if [ -d "${TARGET}/ios-arm64/NodeMobile.framework" ]; then
      echo "==> iOS 运行时已存在，跳过下载"
      exit 0
    fi
    echo "==> 准备 iOS nodejs-mobile 运行时 (v${NODEJS_MOBILE_VERSION})"
    TMP="$(mktemp -d)"
    trap 'rm -rf "${TMP}"' EXIT
    download "${BASE_URL}/nodejs-mobile-v${NODEJS_MOBILE_VERSION}-ios.zip" "${TMP}/nm.zip"
    rm -rf "${TARGET}"
    mkdir -p "$(dirname "${TARGET}")"
    ( cd "${TMP}" && unzip -q nm.zip 'NodeMobile.xcframework/*' -d "${TMP}/x" )
    mv "${TMP}/x/NodeMobile.xcframework" "${TARGET}"
    echo "    -> ${TARGET}"
    ls -1 "${TARGET}" | sed 's/^/       切片: /'
    ;;

  *)
    echo "未知平台: ${PLATFORM}"; exit 1
    ;;
esac

echo "==> 完成"
