/// 表现层：弹幕渲染层（批次 C · C-03）。
///
/// 纯渲染：接收 [DanmakuRenderState] 列表（由
/// `platform/player/danmaku/danmaku_lane_engine.dart` 引擎产出），
/// 以 Stack + Positioned 摆放。弹幕开关 / 透明度 / 区域由外部传入。
library;

import 'package:flutter/material.dart';

import '../../../../platform/player/danmaku/danmaku_lane_engine.dart';

/// 弹幕覆盖层。
class DanmakuOverlay extends StatelessWidget {
  /// 构造。
  const DanmakuOverlay({
    super.key,
    required this.states,
    this.opacity = 0.8,
    this.area = 1.0,
    this.ignorePointer = true,
  });

  /// 引擎产出的当前渲染状态。
  final List<DanmakuRenderState> states;

  /// 不透明度（0.0 ~ 1.0）。
  final double opacity;

  /// 显示区域比例（0.25 ~ 1.0，1.0 全屏）。
  final double area;

  /// 是否忽略指针事件（默认 true：不拦截播放器手势）。
  final bool ignorePointer;

  @override
  Widget build(BuildContext context) {
    if (states.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: ignorePointer,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          for (final DanmakuRenderState s in states)
            Positioned(
              left: s.x,
              top: s.y,
              child: Opacity(
                opacity: opacity,
                child: Text(
                  s.item.content,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: Color(s.item.argb),
                    fontSize: s.item.sizePx,
                    fontWeight: FontWeight.w500,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 2,
                        offset: Offset(1, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
