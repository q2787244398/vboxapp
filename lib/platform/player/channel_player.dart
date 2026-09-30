/// 平台层：通道播放器（实现 [Player]，经 [PlayerChannelBridge] 驱动原生端）。
///
/// 对齐 iOS `AVPlayerEngine` 等内核的宿主侧语义：控制面（open/play/pause/
/// seek/setRate/setVolume/dispose）+ 事件面（state/progress/error）。
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/entities/player/player.dart';
import 'player_channel_bridge.dart';

/// 打开媒体失败（原生错误码 + 消息，供 [PlayerController] 后端链回退）。
class PlayerOpenException implements Exception {
  const PlayerOpenException(this.code, this.message);

  /// 原生错误码（如 `E_BACKEND_UNAVAILABLE`）。
  final String code;

  /// 错误描述。
  final String message;

  @override
  String toString() => 'PlayerOpenException($code): $message';
}

/// 经平台通道调原生播放器（单后端实例）。
///
/// 一个 [ChannelPlayer] 绑定一个 [PlayerBackend]；回退链由
/// [PlayerController] 按后端逐个创建并重试。
class ChannelPlayer implements Player {
  ChannelPlayer({
    required this.backend,
    required PlayerChannelBridge bridge,
  }) : _bridge = bridge {
    _sub = _bridge.events().listen(_onEvent);
  }

  final PlayerChannelBridge _bridge;
  late final StreamSubscription<Map<String, Object?>> _sub;

  @override
  final PlayerBackend backend;

  @override
  List<PlayerBackend> get availableBackends => <PlayerBackend>[backend];

  @override
  void Function(PlayerState)? onStateChanged;

  @override
  void Function(PlaybackProgress)? onProgress;

  @override
  void Function(String message, {required bool fatal})? onError;

  // ─────────────── 控制面 ───────────────

  @override
  Future<void> open(PlayerSource source) async {
    try {
      await _bridge.invoke('open', <String, Object?>{
        ...source.toJson(),
        'backend': backendWireValue(backend),
      });
    } on PlatformException catch (e) {
      throw PlayerOpenException(
        e.code,
        e.message ?? '播放器打开失败（${backend.name}）',
      );
    }
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> seekTo(int positionMs) =>
      _invoke('seekTo', positionMs);

  @override
  Future<void> setVolume(double volume) => _invoke('setVolume', volume);

  @override
  Future<void> setSpeed(double speed) => _invoke('setSpeed', speed);

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    try {
      await _bridge.invoke('dispose');
    } on PlatformException {
      // 原生侧已随引擎销毁，忽略
    }
  }

  // ─────────────── 事件面 ───────────────

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _bridge.invoke(method, arguments);
    } on PlatformException {
      // 控制类方法失败不阻断（状态由 error 事件上报）
    }
  }

  void _onEvent(Map<String, Object?> e) {
    switch ((e['type'] ?? '').toString()) {
      case 'state':
        onStateChanged?.call(_parseState((e['value'] ?? '').toString()));
      case 'progress':
        onProgress?.call(PlaybackProgress(
          positionMs: (e['positionMs'] as num?)?.toInt() ?? 0,
          durationMs: (e['durationMs'] as num?)?.toInt() ?? 0,
          bufferedMs: (e['bufferedMs'] as num?)?.toInt() ?? 0,
          isLive: e['isLive'] as bool? ?? false,
        ));
      case 'error':
        onError?.call(
          (e['message'] ?? '').toString(),
          fatal: e['fatal'] as bool? ?? true,
        );
    }
  }

  static PlayerState _parseState(String value) => switch (value) {
        'idle' => PlayerState.idle,
        'opening' => PlayerState.opening,
        'playing' => PlayerState.playing,
        'paused' => PlayerState.paused,
        'buffering' => PlayerState.buffering,
        'ended' => PlayerState.ended,
        'error' => PlayerState.error,
        _ => PlayerState.idle,
      };
}
