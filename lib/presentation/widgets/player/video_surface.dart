/// 表现层：视频输出面（Wave A · R-渲1）。
///
/// 以原生 `open` 返回的 Flutter textureId 承载画面（[Texture]）；无纹理
/// （控制面后端 / 未开播）时渲染深色占位，避免「有声无画」被误判为黑屏故障。
///
/// 纵横比按 [aspectRatio] 自适应（对齐 iOS `AVPlayerLayer.videoGravity =
/// .resizeAspect`）：已知视频尺寸时居中留边，未知时铺满（交由原生缩放）。
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
    this.filterQuality = FilterQuality.low,
  });

  /// 原生纹理句柄（null = 无纹理输出 → 深色占位）。
  final int? textureId;

  /// 视频纵横比（宽 / 高；null / 非法值 = 铺满）。
  final double? aspectRatio;

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
    return Center(
      child: AspectRatio(aspectRatio: ar, child: surface),
    );
  }
}