#!/usr/bin/env pwsh
# 批次 G-03-B：编译 quickjs/wrapper.c → vbox_quickjs.dll（Windows JS 引擎）。
#
# QuickJS 源码依赖 GCC 扩展（`__int128` / `__attribute__`，见 libbf.h / cutils.h），
# **MSVC 无法编译** → 用 MSYS2 mingw-w64 gcc（x86_64-w64-mingw32-gcc）。
# 复用跨端脚本 scripts/build_quickjs_wrapper.sh（其 `uname` 分支对 MINGW 产出 .dll）。
#
# 产物（build/vbox-quickjs/）：
#   vbox_quickjs.dll   wrapper（导出 vq_* 十一符号：同步 eval + worker/http 桥）
# 运行时依赖：mingw 侧 -static-libgcc + 静态 winpthread（见 build_quickjs_wrapper.sh），
# 无额外随之分发的 DLL；Dart 侧 DLL 名与 quickjs_ffi.dart 一致（vbox_quickjs.dll）。
#
# 前置（CI）：msys2/setup-msys2 提供 mingw-w64-x86_64-gcc；
# 或本机 MSYS2 默认安装（C:\msys64）。
#
# 用法：pwsh scripts/build-quickjs-windows.ps1 [-OutDir <dir>]
param(
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) {
    $OutDir = Join-Path $root "build/vbox-quickjs"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ── 定位 MSYS2 bash + mingw-w64 gcc ──
$bashCandidates = @(
    "C:\msys64\usr\bin\bash.exe",
    "C:\tools\msys64\usr\bin\bash.exe",
    $env:MSYS2_BASH
) | Where-Object { $_ -and (Test-Path $_) }
if ($bashCandidates.Count -eq 0) {
    throw "未找到 MSYS2 bash（期望 C:\msys64\usr\bin\bash.exe）。CI 需先 msys2/setup-msys2 安装 mingw-w64-x86_64-gcc。"
}
$bash = $bashCandidates[0]

# Windows 路径 → MSYS2 POSIX 路径（C:\a\b → /c/a/b）
function ConvertTo-MsysPath([string]$p) {
    $q = $p -replace '\\', '/'
    if ($q -match '^([A-Za-z]):(.*)$') { return "/" + $matches[1].ToLower() + $matches[2] }
    return $q
}
$rootPosix = ConvertTo-MsysPath $root
$outPosix = ConvertTo-MsysPath $OutDir

Write-Host "🏗️  编译 vbox_quickjs.dll（mingw-w64 gcc）"
& $bash -lc "set -euo pipefail; export PATH=/mingw64/bin:\$PATH; cd '$rootPosix'; CC=x86_64-w64-mingw32-gcc bash scripts/build_quickjs_wrapper.sh '$outPosix'"
if ($LASTEXITCODE -ne 0) { throw "build_quickjs_wrapper.sh 失败（$LASTEXITCODE）" }

# Dart 侧 quickjs_ffi.dart 按 Windows 约定加载 `vbox_quickjs.dll`（无 lib 前缀）
$built = Join-Path $OutDir "libvbox_quickjs.dll"
$dll = Join-Path $OutDir "vbox_quickjs.dll"
if (-not (Test-Path $built)) { throw "未产出 $built" }
Move-Item -Force $built $dll

# ── 符号级冒烟：vq_* 十一导出（同步 + 宿主桥）──
Write-Host "🔎 符号校验（vq_* 十一导出）"
$symList = @(
    "vq_create_runtime", "vq_create_context", "vq_free_runtime", "vq_free_context",
    "vq_eval", "vq_free_string", "vq_free_buffer", "vq_set_host_bridge",
    "vq_eval_submit", "vq_eval_take_result", "vq_http_complete"
)
$nm = "C:\msys64\mingw64\bin\x86_64-w64-mingw32-nm.exe"
if (-not (Test-Path $nm)) { $nm = "x86_64-w64-mingw32-nm" }
$exports = (& $nm -g --defined-only $dll | Out-String)
$missing = @()
foreach ($sym in $symList) {
    if ($exports -notmatch ("\b" + [regex]::Escape($sym) + "\b")) { $missing += $sym }
}
if ($missing.Count -gt 0) { throw "缺导出符号：$($missing -join ', ')" }
$sizeMB = [math]::Round((Get-Item $dll).Length / 1MB, 2)
Write-Host "✅ vq_* 十一符号 ✓ · vbox_quickjs.dll（$sizeMB MB）"