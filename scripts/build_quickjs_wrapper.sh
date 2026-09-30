#!/usr/bin/env bash
# 编译 vbox QuickJS FFI wrapper（G-03-B-1）—— 纯 C，三端通用（CI ubuntu 验证用）。
#
# 用法：scripts/build_quickjs_wrapper.sh [输出目录]
# 默认输出到 /tmp/vbox_quickjs_build/，产物 libvbox_quickjs.so（Windows 为 .dll）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/vbox_quickjs_build}"
QJS="$ROOT/quickjs/quickjs-2024-01-13"

mkdir -p "$OUT"

CC="${CC:-gcc}"
EXT="so"
case "$(uname -s)" in
  Darwin) EXT="dylib" ;;
  MINGW*|MSYS*|CYGWIN*) EXT="dll" ;;
esac

# 与 quickjs Makefile 一致的必要宏
DEFS=(-DCONFIG_VERSION="\"$(cat "$QJS/VERSION" 2>/dev/null || echo 2024-01-13)\"")
LIBS=()
if [ "$EXT" = "dylib" ] || [ "$EXT" = "so" ]; then
  LIBS=(-lm)
fi

"$CC" -shared -fPIC -O2 "${DEFS[@]}" -I "$QJS" -o "$OUT/libvbox_quickjs.$EXT" \
  "$ROOT/quickjs/wrapper.c" \
  "$QJS/quickjs.c" \
  "$QJS/cutils.c" \
  "$QJS/libbf.c" \
  "$QJS/libregexp.c" \
  "$QJS/libunicode.c" \
  "${LIBS[@]}"

echo "✅ 编译完成：$OUT/libvbox_quickjs.$EXT"
