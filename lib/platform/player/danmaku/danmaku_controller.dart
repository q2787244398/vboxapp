/// 平台层：弹幕播放控制器（批次 C · C-03）。
///
/// 持有全量弹幕（按时间升序）与 [DanmakuLaneEngine]，按播放位置喂入
/// 「到期」弹幕并产出渲染状态。播放器页面每帧/定时调用 [tick]。
library;

import 'danmaku_item.dart';
import 'danmaku_lane_engine.dart';

/// 弹幕播放控制器（C-03）。
class DanmakuPlaybackController {
  /// 构造（[items] 复制并按 timeMs 升序；[engine] 可注入）。
  DanmakuPlaybackController({
    required List<DanmakuItem> items,
    DanmakuLaneEngine? engine,
  })  : _items = List<DanmakuItem>.of(items)
          ..sort((DanmakuItem a, DanmakuItem b) => a.timeMs.compareTo(b.timeMs)),
        _engine = engine ?? DanmakuLaneEngine();

  final List<DanmakuItem> _items;
  final DanmakuLaneEngine _engine;
  int _cursor = 0;

  /// 底层引擎（供渲染层取参数）。
  DanmakuLaneEngine get engine => _engine;

  /// 总弹幕数。
  int get totalCount => _items.length;

  /// 是否还有未出场的弹幕。
  bool get hasMore => _cursor < _items.length;

  /// 推进到 [nowMs]：喂入到期弹幕，返回当前应渲染的状态列表。
  List<DanmakuRenderState> tick(int nowMs) {
    final List<DanmakuItem> incoming = <DanmakuItem>[];
    while (_cursor < _items.length && _items[_cursor].timeMs <= nowMs) {
      incoming.add(_items[_cursor]);
      _cursor++;
    }
    return _engine.compute(nowMs, incoming);
  }

  /// 重置（切换视频 / 重播）。
  void reset() {
    _cursor = 0;
    _engine.reset();
  }
}
