#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# G-02-C（D28）：libmpv 原生二进制分发 —— 不入 git 仓库，
# 由本脚本从 GitHub Release 资产下载（libmpv-{os}-{arch}-{ver}.{dylib|dll} + sha256），
# 随侧载产物（DMG / EXE）分发。沿用 iOS mpvkit-deps 模式（fetch_mpv_dependencies.sh）：
# 私有仓库 release 资产走 GitHub API 资产端点（releases/assets/{id} + octet-stream）。

# ─────────────── 参数 / 环境变量（带默认） ───────────────
LIBMPV_DEPS_REPO="${LIBMPV_DEPS_REPO:-q2787244398/vbox-deps}"
LIBMPV_DEPS_TAG="${LIBMPV_DEPS_TAG:-libmpv-deps-0.0.1}"
LIBMPV_DEPS_VERSION="${LIBMPV_DEPS_VERSION:-0.0.1}"
LIBMPV_DEPS_OS="${LIBMPV_DEPS_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
LIBMPV_DEPS_ARCH="${LIBMPV_DEPS_ARCH:-$(uname -m)}"
LIBMPV_DEPS_CACHE_DIR="${LIBMPV_DEPS_CACHE_DIR:-.mpv-cache}"
LIBMPV_DEPS_TOKEN="${LIBMPV_DEPS_TOKEN:-${GITHUB_TOKEN:-}}"

# 直链覆盖（镜像 / 自定义地址）：设置 LIBMPV_DEPS_URL 时改走普通 curl。
LIBMPV_DEPS_URL="${LIBMPV_DEPS_URL:-}"
LIBMPV_DEPS_SHA256_URL="${LIBMPV_DEPS_SHA256_URL:-}"

usage() {
    cat <<'USAGE'
用法: scripts/fetch_libmpv.sh [选项]

选项:
  --os <os>            目标系统（macos / windows / linux；默认本机 uname -s）
  --arch <arch>        目标架构（arm64 / x86_64；默认本机 uname -m）
  --tag <tag>          GitHub Release tag（默认 libmpv-deps-0.0.1，也可用 LIBMPV_DEPS_TAG）
  --version <ver>      资产版本段（默认 0.0.1，也可用 LIBMPV_DEPS_VERSION）
  --repo <repo>        GitHub 仓库（默认 q2787244398/vbox-deps，也可用 LIBMPV_DEPS_REPO）
  --url <url>          显式直链 URL，覆盖 API 方式（也可用 LIBMPV_DEPS_URL）
  --sha256-url <url>   sha256 文件直链地址（默认 <url>.sha256）
  --token <token>      访问私有仓库 release 的认证 token（也可用 LIBMPV_DEPS_TOKEN / GITHUB_TOKEN）
  --cache-dir <dir>    输出/缓存目录（默认 .mpv-cache，也可用 LIBMPV_DEPS_CACHE_DIR）
  -h, --help           打印帮助

资产命名（D28）：libmpv-{os}-{arch}-{ver}.{ext}
  macos   → libmpv-macos-{arch}-{ver}.dylib
  windows → libmpv-windows-{arch}-{ver}.dll
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --os) LIBMPV_DEPS_OS="$2"; shift 2 ;;
        --arch) LIBMPV_DEPS_ARCH="$2"; shift 2 ;;
        --tag) LIBMPV_DEPS_TAG="$2"; shift 2 ;;
        --version) LIBMPV_DEPS_VERSION="$2"; shift 2 ;;
        --repo) LIBMPV_DEPS_REPO="$2"; shift 2 ;;
        --url) LIBMPV_DEPS_URL="$2"; shift 2 ;;
        --sha256-url) LIBMPV_DEPS_SHA256_URL="$2"; shift 2 ;;
        --token) LIBMPV_DEPS_TOKEN="$2"; shift 2 ;;
        --cache-dir) LIBMPV_DEPS_CACHE_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# 架构归一（macOS 本机 arm64 / x86_64）
case "$LIBMPV_DEPS_ARCH" in
    amd64|x64) LIBMPV_DEPS_ARCH="x86_64" ;;
    aarch64|arm64) LIBMPV_DEPS_ARCH="arm64" ;;
esac

# 扩展名（D28：dylib / dll）
case "$LIBMPV_DEPS_OS" in
    macos) LIBMPV_DEPS_EXT="dylib" ;;
    windows) LIBMPV_DEPS_EXT="dll" ;;
    *) echo "不支持的 os: $LIBMPV_DEPS_OS（仅 macos / windows）" >&2; exit 1 ;;
esac

ASSET_NAME="libmpv-${LIBMPV_DEPS_OS}-${LIBMPV_DEPS_ARCH}-${LIBMPV_DEPS_VERSION}.${LIBMPV_DEPS_EXT}"
DEST_DIR="${LIBMPV_DEPS_CACHE_DIR}"
mkdir -p "${DEST_DIR}"
DEST="${DEST_DIR}/${ASSET_NAME}"

# 若已下载且校验通过 → 直接复用
if [ -f "${DEST}" ] && [ -f "${DEST}.sha256" ] && \
   [ "$(cat "${DEST}.sha256")" = "$(shasum -a 256 "${DEST}" | awk '{print $1}')" ]; then
    echo "✅ 已缓存并校验通过: ${DEST}"
    exit 0
fi

if [ -z "${LIBMPV_DEPS_TOKEN}" ] && [ -z "${LIBMPV_DEPS_URL}" ]; then
    echo "⚠️ 未提供 LIBMPV_DEPS_TOKEN / GITHUB_TOKEN 且未指定 --url；私有仓库资产下载需认证。" >&2
    echo "   （本地可先 gh auth login，脚本会自动尝试复用 gh CLI 的 token）" >&2
fi

# 直链模式
if [ -n "${LIBMPV_DEPS_URL}" ]; then
    SHA_URL="${LIBMPV_DEPS_SHA256_URL:-${LIBMPV_DEPS_URL}.sha256}"
    echo "⬇️  直链下载 ${LIBMPV_DEPS_URL}"
    curl -fL --retry 3 -o "${DEST}" "${LIBMPV_DEPS_URL}"
    curl -fsL --retry 3 -o "${DEST}.sha256" "${SHA_URL}" || echo "(sha256 直链不可得，跳过)"
    EXPECTED="$(cat "${DEST}.sha256")"
    ACTUAL="$(shasum -a 256 "${DEST}" | awk '{print $1}')"
    if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "❌ sha256 校验失败" >&2; exit 1
    fi
    echo "✅ 下载完成（sha256 ${ACTUAL}）: ${DEST}"
    exit 0
fi

# GitHub API 资产端点模式（私有仓库需认证）
echo "⬇️  GitHub Release 下载 ${ASSET_NAME} @ ${LIBMPV_DEPS_REPO}:${LIBMPV_DEPS_TAG}"
AUTH_HEADER=()
if [ -n "${LIBMPV_DEPS_TOKEN}" ]; then
    AUTH_HEADER=(-H "Authorization: Bearer ${LIBMPV_DEPS_TOKEN}")
fi

# 取资产 id（按 name 精确匹配）
ASSET_JSON="$(curl -fsL "${AUTH_HEADER[@]}" \
    "https://api.github.com/repos/${LIBMPV_DEPS_REPO}/releases/tags/${LIBMPV_DEPS_TAG}")"
ASSET_ID="$(printf '%s' "$ASSET_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((a['id'] for a in d.get('assets',[]) if a['name']=='$ASSET_NAME'),''))")"
if [ -z "${ASSET_ID}" ]; then
    echo "❌ 资产不存在: ${ASSET_NAME}（tag=${LIBMPV_DEPS_TAG}，repo=${LIBMPV_DEPS_REPO}）" >&2
    exit 1
fi

curl -fL "${AUTH_HEADER[@]}" \
    -H "Accept: application/octet-stream" \
    -o "${DEST}" \
    "https://api.github.com/repos/${LIBMPV_DEPS_REPO}/releases/assets/${ASSET_ID}"

# 校验和：优先 .sha256 资产，其次清单登记
SHA_ASSET_NAME="${ASSET_NAME}.sha256"
SHA_ASSET_ID="$(printf '%s' "$ASSET_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((a['id'] for a in d.get('assets',[]) if a['name']=='$SHA_ASSET_NAME'),''))")"
EXPECTED=""
if [ -n "${SHA_ASSET_ID}" ]; then
    curl -fsL "${AUTH_HEADER[@]}" \
        -H "Accept: application/octet-stream" \
        -o "${DEST}.sha256" \
        "https://api.github.com/repos/${LIBMPV_DEPS_REPO}/releases/assets/${SHA_ASSET_ID}"
    EXPECTED="$(cat "${DEST}.sha256")"
fi
ACTUAL="$(shasum -a 256 "${DEST}" | awk '{print $1}')"
if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "❌ sha256 校验失败（期望 ${EXPECTED}，实际 ${ACTUAL}）" >&2; exit 1
fi

echo "✅ 下载完成（sha256 ${ACTUAL}）: ${DEST}"
