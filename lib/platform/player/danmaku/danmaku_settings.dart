/// 平台层：弹幕设置（批次 C · C-03）。
///
/// - 会话级显示参数（开 / 透明度 / 字号 / 显示区域）：契约 99 键已冻结，
///   不持久化，由弹幕设置面板在播放会话内调整（默认 开 / 0.8 / 16px / 1.0）。
/// - 自定义弹幕源（开关 + 地址）：走契约键 `custom_danmaku_source_enabled` /
///   `custom_danmaku_source_url`，经 [PlaybackSettings.loadWithDanmaku] 读取。
library;

import '../playback_settings.dart';

/// 会话级弹幕显示设置快照（不可变）。
class DanmakuSettings {
  /// 构造。
  const DanmakuSettings({
    required this.enabled,
    required this.opacity,
    required this.fontSize,
    required this.area,
    required this.customSourceEnabled,
    required this.customSourceUrl,
  });

  /// 默认值（开 / 0.8 / 16px / 1.0；自定义源关 + 空地址）。
  static const DanmakuSettings defaults = DanmakuSettings(
    enabled: true,
    opacity: 0.8,
    fontSize: 16,
    area: 1.0,
    customSourceEnabled: false,
    customSourceUrl: '',
  );

  /// 弹幕开关。
  final bool enabled;

  /// 不透明度（0.0 ~ 1.0）。
  final double opacity;

  /// 字号（px）。
  final double fontSize;

  /// 显示区域（0.25 ~ 1.0，1.0 全屏）。
  final double area;

  /// 自定义弹幕源开关。
  final bool customSourceEnabled;

  /// 自定义弹幕源地址。
  final String customSourceUrl;

  /// 复制并修改部分字段。
  DanmakuSettings copyWith({
    bool? enabled,
    double? opacity,
    double? fontSize,
    double? area,
    bool? customSourceEnabled,
    String? customSourceUrl,
  }) =>
      DanmakuSettings(
        enabled: enabled ?? this.enabled,
        opacity: opacity ?? this.opacity,
        fontSize: fontSize ?? this.fontSize,
        area: area ?? this.area,
        customSourceEnabled: customSourceEnabled ?? this.customSourceEnabled,
        customSourceUrl: customSourceUrl ?? this.customSourceUrl,
      );

  /// 由播放行为设置构建弹幕显示设置（会话参数保持默认，自定义源取自契约）。
  static DanmakuSettings fromPlayback(PlaybackSettings p) => DanmakuSettings(
        enabled: true,
        opacity: 0.8,
        fontSize: 16,
        area: 1.0,
        customSourceEnabled: p.customDanmakuSourceEnabled,
        customSourceUrl: p.customDanmakuSourceUrl,
      );

  /// 异步加载：播放设置（含自定义弹幕源契约键）+ 会话默认显示参数。
  static Future<DanmakuSettings> load() async {
    final PlaybackSettings p = await PlaybackSettings.loadWithDanmaku();
    return fromPlayback(p);
  }

  /// 校验显示参数合法（面板滑块用：clamp 后回写）。
  DanmakuSettings normalized() => copyWith(
        opacity: opacity.clamp(0.1, 1.0),
        fontSize: fontSize.clamp(10, 32),
        area: area.clamp(0.25, 1.0),
      );

  @override
  String toString() =>
      'DanmakuSettings(en=$enabled, op=$opacity, size=$fontSize, area=$area, '
      'custom=$customSourceEnabled)';
}
