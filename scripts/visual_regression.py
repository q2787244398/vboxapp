#!/usr/bin/env python3
"""视觉回归比对（批次 A · A-12）。

依据：docs/第2轮开发计划_功能补全_v2.5.md §3.6「保真度 ≥95% 的可度量定义」——
逐页 SSIM ≥ 0.95（或像素差 ≤5%）为主要指标；§3.7 视觉回归与守卫。

用法：
    python3 scripts/visual_regression.py --ref docs/ui_baseline --cmp <flt截图目录> [--threshold 0.95] [--gate]

- `--ref`  参考图目录（iOS UI 基准图 docs/ui_baseline/*.png）
- `--cmp`  Flutter 侧截图目录（与本仓页面同名 PNG）
- `--threshold`  SSIM 门槛（默认 0.95，仅报告）
- `--gate`   低于门槛即返回非 0（CI 门禁用，默认关闭：报告模式）

产出：逐页 SSIM + 均值 + 低于门槛清单。退出码：0 通过 / 1 不达标（--gate 时）。
"""
from __future__ import annotations

import argparse
import pathlib
import sys

import cv2
import numpy as np


def ssim(a: np.ndarray, b: np.ndarray) -> float:
    """结构相似度（灰度，0–1）。"""
    a = cv2.cvtColor(a, cv2.COLOR_RGB2GRAY).astype(np.float64)
    b = cv2.cvtColor(b, cv2.COLOR_RGB2GRAY).astype(np.float64)
    return _ssim_impl(a, b)


def _ssim_impl(a: np.ndarray, b: np.ndarray) -> float:
    """标准 SSIM（窗口 11×11 高斯，σ=1.5）。"""
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    kernel = cv2.getGaussianKernel(11, 1.5)
    window = kernel @ kernel.T
    mu_a = cv2.filter2D(a, -1, window)
    mu_b = cv2.filter2D(b, -1, window)
    mu_a2, mu_b2, mu_ab = mu_a * mu_a, mu_b * mu_b, mu_a * mu_b
    sigma_a2 = cv2.filter2D(a * a, -1, window) - mu_a2
    sigma_b2 = cv2.filter2D(b * b, -1, window) - mu_b2
    sigma_ab = cv2.filter2D(a * b, -1, window) - mu_ab
    ssim_map = ((2 * mu_ab + c1) * (2 * sigma_ab + c2)) / (
        (mu_a2 + mu_b2 + c1) * (sigma_a2 + sigma_b2 + c2)
    )
    return float(ssim_map.mean())


def _load(path: pathlib.Path) -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"无法读取图片：{path}")
    return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ref", required=True, type=pathlib.Path)
    ap.add_argument("--cmp", required=True, type=pathlib.Path)
    ap.add_argument("--threshold", type=float, default=0.95)
    ap.add_argument("--gate", action="store_true")
    args = ap.parse_args()

    ref_dir, cmp_dir = args.ref, args.cmp
    print("== 视觉回归比对（SSIM）==")
    if not ref_dir.is_dir() or not cmp_dir.is_dir():
        print("  ❌ --ref / --cmp 需为存在目录")
        return 1

    refs = {p.name: p for p in ref_dir.glob("*.png")}
    cmps = {p.name: p for p in cmp_dir.glob("*.png")}
    if not refs or not cmps:
        print("  ❌ 目录内无 PNG（refs=%d cmps=%d）" % (len(refs), len(cmps)))
        return 1

    names = sorted(refs.keys() & cmps.keys())
    if not names:
        print("  ❌ 无同名 PNG（ref=%s cmp=%s）" % (sorted(refs)[:5], sorted(cmps)[:5]))
        return 1

    scores: dict[str, float] = {}
    for name in names:
        a = _load(refs[name])
        b = _load(cmps[name])
        # 尺寸不同先对齐（缩放到较小尺寸，保持宽高比）
        if a.shape != b.shape:
            h = min(a.shape[0], b.shape[0])
            w = min(a.shape[1], b.shape[1])
            a = cv2.resize(a, (w, h))
            b = cv2.resize(b, (w, h))
        scores[name] = ssim(a, b)

    for name in names:
        mark = "✅" if scores[name] >= args.threshold else "❌"
        print(f"  {mark} {name:<24} SSIM = {scores[name]:.3f}")

    mean = float(np.mean(list(scores.values())))
    below = [n for n in names if scores[n] < args.threshold]
    print(f"  同名 {len(names)} 张 · 均值 SSIM = {mean:.3f} · 门槛 {args.threshold:.2f}")
    if below:
        print(f"  ⚠️  低于门槛 {len(below)} 张：{', '.join(below)}")
        if args.gate:
            print("视觉回归比对: 失败 ❌")
            return 1
    print("视觉回归比对: 通过 ✅（报告模式）" if not below else "视觉回归比对: 通过 ✅（报告模式，未门禁）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
