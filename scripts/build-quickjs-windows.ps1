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
# 关键：必须在**含 mingw gcc 的那个** MSYS2 根下编译。GitHub 镜像可能自带一个
# C:\msys64（无 gcc），而 msys2/setup-msys2 安装的带 gcc 实例未必同根 —— 若只按
# 路径存在性挑 bash，会挑到无 gcc 的根，报「x86_64-w64-mingw32-gcc: command not
# found」。故按「该根下存在 mingw64\bin\x86_64-w64-mingw32-gcc.exe」逐个校验，
# 命中的根即为编译根。
# 候选顺序：PATH 上的 bash（setup-msys2 会把其 usr\bin 前置）→ 常见位置 → 环境变量。
# 外层 @() 强制数组：Where-Object 仅命中一项时管道结果会被解包为字符串。
$candidates = @(
    @(
        (Get-Command bash.exe -ErrorAction SilentlyContinue).Source,
        "C:\msys64\usr\bin\bash.exe",
        "C:\tools\msys64\usr\bin\bash.exe",
        $env:MSYS2_BASH
    ) | Where-Object { $_ -and (Test-Path $_) }
)
$bash = $null
$msysRoot = $null
foreach ($c in $candidates) {
    # MSYS2 根由 bash 路径反推（<root>\usr\bin\bash.exe）
    $r = Split-Path (Split-Path (Split-Path $c -Parent) -Parent) -Parent
    if (Test-Path (Join-Path $r "mingw64\bin\x86_64-w64-mingw32-gcc.exe")) {
        $bash = $c
        $msysRoot = $r
        break
    }
}
if (-not $bash) {
    throw "未找到含 mingw-w64 gcc 的 MSYS2 bash（候选：$($candidates -join '; ')）。CI 需 msys2/setup-msys2 安装 mingw-w64-x86_64-gcc。"
}
Write-Host "🧰 MSYS2 根：$msysRoot"

# Windows 路径 → MSYS2 POSIX 路径（C:\a\b → /c/a/b）
function ConvertTo-MsysPath([string]$p) {
    $q = $p -replace '\\', '/'
    if ($q -match '^([A-Za-z]):(.*)$') { return "/" + $matches[1].ToLower() + $matches[2] }
    return $q
}
$rootPosix = ConvertTo-MsysPath $root
$outPosix = ConvertTo-MsysPath $OutDir
$msysRootPosix = ConvertTo-MsysPath $msysRoot

Write-Host "🏗️  编译 vbox_quickjs.dll（mingw-w64 gcc）"
# 注意（两处转义坑）：
#   1) PowerShell 双引号串内转义 `$` 须用**反引号**（`` `$ ``），反斜杠无效 ——
#      原 `\$PATH` 会被解析为字面 `\` + 展开空变量 → bash 收到
#      `export PATH=/mingw64/bin:\; cd '...'`（`\;` 吞掉分号）→
#      报「export: '/d/a/...': not a valid identifier」。
#   2) MSYS2 PATH 项可能含空格（如 `/c/Program Files/...`），故 PATH 赋值整体加
#      双引号（PowerShell 侧写作 `` `" ``）。
# MSYSTEM=MINGW64 + 显式前置该根下的 mingw64/bin：避免 login shell 的 profile
# 在非 MINGW64 会话下不注入工具链路径。
& $bash -lc "set -euo pipefail; export MSYSTEM=MINGW64; export PATH=`"$msysRootPosix/mingw64/bin:$msysRootPosix/usr/bin:`$PATH`"; cd '$rootPosix'; CC=x86_64-w64-mingw32-gcc bash scripts/build_quickjs_wrapper.sh '$outPosix'"
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
$nm = Join-Path $msysRoot "mingw64\bin\x86_64-w64-mingw32-nm.exe"
if (-not (Test-Path $nm)) { $nm = "x86_64-w64-mingw32-nm" }
$exports = (& $nm -g --defined-only $dll | Out-String)
$missing = @()
foreach ($sym in $symList) {
    if ($exports -notmatch ("\b" + [regex]::Escape($sym) + "\b")) { $missing += $sym }
}
if ($missing.Count -gt 0) { throw "缺导出符号：$($missing -join ', ')" }
$sizeMB = [math]::Round((Get-Item $dll).Length / 1MB, 2)
Write-Host "✅ vq_* 十一符号 ✓ · vbox_quickjs.dll（$sizeMB MB）"