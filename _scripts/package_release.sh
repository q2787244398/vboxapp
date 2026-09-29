#!/usr/bin/env bash
#
# 把各平台构建产物打成该平台「原生的安装包」，输出到仓库根的 dist/。
#
#   android -> .apk      （Android 安装包，原样取出）
#   ios     -> .ipa      （Payload/Runner.app 打包；巨魔/TrollStore 可直接安装未签名 IPA）
#   macos   -> .dmg      （hdiutil 生成磁盘映像）
#   windows -> .exe      （Inno Setup 生成安装程序；找不到 ISCC 时退化为便携版 zip）
#
# 用法: bash _scripts/package_release.sh <android|ios|macos|windows> <版本号>
set -euo pipefail

PLATFORM="${1:?用法: package_release.sh <android|ios|macos|windows> <版本号>}"
VERSION="${2:?需要版本号，例如 1.2.2}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
APP="${ROOT}/flutter"
DIST="${ROOT}/dist"
mkdir -p "${DIST}"

echo "==> 打包 ${PLATFORM} -> ${DIST}"

case "${PLATFORM}" in
  android)
    APK="${APP}/build/app/outputs/flutter-apk/app-release.apk"
    [ -f "${APK}" ] || { echo "找不到 APK: ${APK}"; exit 1; }
    cp "${APK}" "${DIST}/TVS-${VERSION}-android.apk"
    ;;

  ios)
    BUNDLE="${APP}/build/ios/iphoneos/Runner.app"
    [ -d "${BUNDLE}" ] || { echo "找不到 Runner.app: ${BUNDLE}"; exit 1; }
    # IPA 的标准结构就是一个 zip，内含 Payload/<App>.app
    WORK="${DIST}/.ipa-work"
    rm -rf "${WORK}"
    mkdir -p "${WORK}/Payload"
    cp -R "${BUNDLE}" "${WORK}/Payload/"
    rm -f "${DIST}/TVS-${VERSION}-ios.ipa"
    ( cd "${WORK}" && zip -qry "${DIST}/TVS-${VERSION}-ios.ipa" Payload )
    rm -rf "${WORK}"
    ;;

  macos)
    BUNDLE="$(ls -d "${APP}/build/macos/Build/Products/Release/"*.app 2>/dev/null | head -n 1 || true)"
    [ -n "${BUNDLE}" ] || { echo "找不到 macOS .app"; exit 1; }
    echo "    源: ${BUNDLE}"
    rm -f "${DIST}/TVS-${VERSION}-macos.dmg"
    hdiutil create \
      -volname "TVS ${VERSION}" \
      -srcfolder "${BUNDLE}" \
      -ov -format UDZO \
      "${DIST}/TVS-${VERSION}-macos.dmg"
    ;;

  windows)
    SRC="${APP}/build/windows/x64/runner/Release"
    [ -d "${SRC}" ] || { echo "找不到 Windows 构建输出: ${SRC}"; exit 1; }

    ISCC=""
    for candidate in \
      "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
      "/c/Program Files/Inno Setup 6/ISCC.exe" \
      "/c/Program Files (x86)/Inno Setup 5/ISCC.exe"; do
      if [ -f "${candidate}" ]; then ISCC="${candidate}"; break; fi
    done

    if [ -z "${ISCC}" ]; then
      echo "!! 未找到 Inno Setup，退化为便携版 zip（非安装程序）"
      rm -f "${DIST}/TVS-${VERSION}-windows-portable.zip"
      ( cd "${SRC}/.." && zip -qr "${DIST}/TVS-${VERSION}-windows-portable.zip" Release )
      exit 0
    fi

    echo "    使用: ${ISCC}"
    WSRC="$(cygpath -w "${SRC}")"
    WDIST="$(cygpath -w "${DIST}")"
    WISS="${DIST}/.tvs-win.iss"

    # 由模板生成实际脚本。不用 ISCC 的 /D 参数，因为 Git Bash(MSYS) 会把
    # 以 / 开头的参数当作 Unix 路径自动改写，导致
    # "You may not specify more than one script filename."。
    # Windows 上 Python 的 stdout 默认是 cp1252，输出非 ASCII 会抛
    # UnicodeEncodeError。这里只用 ASCII 打印，并显式指定 PYTHONIOENCODING 兜底。
    PYTHONIOENCODING=utf-8 python3 - "${ROOT}/packaging/windows/tvs.iss.in" "${WISS}" "${VERSION}" "${WSRC}" "${WDIST}" <<'PY'
import sys
tpl, out, ver, src, dst = sys.argv[1:6]
text = open(tpl, encoding='utf-8').read()
text = (text.replace('@@MYAPPVERSION@@', ver)
            .replace('@@SOURCEDIR@@', src)
            .replace('@@OUTPUTDIR@@', dst))
if '@@' in text:
    sys.exit('ERROR: unreplaced placeholder remains in template')
# Inno Setup 需要能识别编码；带 BOM 的 UTF-8 最稳妥
open(out, 'w', encoding='utf-8-sig').write(text)
print(f'    generated iss: {out}')
PY

    # 只传一个参数（脚本路径），彻底避开 MSYS 参数转换
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "${ISCC}" "$(cygpath -w "${WISS}")"
    rm -f "${WISS}"
    ;;

  *)
    echo "未知平台: ${PLATFORM}"; exit 1
    ;;
esac

echo "==> dist/ 内容:"
ls -lh "${DIST}" | sed 's/^/    /'
