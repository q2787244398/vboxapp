/// 表现层：视频输出面（Wave A · R-渲1；UI-E2 补画面拉伸模式）。
///
/// 以原生 `open` 返回的 Flutter textureId 承载画面（[Texture]）；无纹理
/// （控制面后端 / 未开播）时渲染深色占位，避免「有声无画」被误判为黑屏故障。
///
/// 缩放模式（UI-E2，对齐 iOS `AVPlayerLayer.videoGravity`，缺省 `.contain`）：
///  - `contain`（适应）：已知视频尺寸时居中留边（对齐 iOS `.resizeAspect`）；
///  - `cover`（填充）：保持宽高比铺满裁切（对齐 iOS `.resizeAspectFill`）；
///  - `fill`（拉伸）：强制适配视图宽高比（对齐 iOS `.resize`）。
/// 未知尺寸时一律铺满（交由原生缩放）。
library;

import 'package:flutter/material.dart';

import '../../theme/tokens/colors.dart';

/// 视频输出面。
class VideoSurface extends StatelessWidget {
  /// 构造。
  const VideoSurface({
    super.key,
    this.textureId,
    this.aspectRatio,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.low,
  });

  /// 原生纹理句柄（null = 无纹理输出 → 深色占位）。
  final int? textureId;

  /// 视频纵横比（宽 / 高；null / 非法值 = 铺满）。
  final double? aspectRatio;

  /// 缩放模式（UI-E2；仅已知纵横比时区分，未知尺寸一律铺满）。
  final BoxFit fit;

  /// 纹理采样质量（播放器画面取 low 足够，避免高开销重采样）。
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final int? id = textureId;
    if (id == null) {
      return const ColoredBox(color: VboxColors.playerBackground);
    }
    final Widget surface = Texture(
      textureId: id,
      filterQuality: filterQuality,
    );
    final double? ar = aspectRatio;
    if (ar == null || ar <= 0 || ar.isNaN || ar.isInfinite) {
      return surface;
    }
    if (fit == BoxFit.contain) {
      return Center(
        child: AspectRatio(aspectRatio: ar, child: surface),
      );
    }
    // 填充 / 拉伸：以视频纵横比作为子盒，由 FittedBox 按目标模式缩放。
    return FittedBox(
      fit: fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: ar, height: 1, child: surface),
    );
  }
}
