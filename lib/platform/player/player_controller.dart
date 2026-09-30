/// 平台层：播放器统一控制层（映射 iOS `PlayerEngineController`）。
///
/// 职责：
///  - 持有当前播放器实例 + 后端降级链（契约 §2.5 + A21.5 的 Dart 侧语义）
///  - `open` 失败时按链回退（A21.5 selectBackend：复杂封装 / HEVC 无硬解走 libVLC）
///  - 状态 / 进度 / 错误回调转发（对齐 iOS `PlayerEngineState` + `PlayerEngineEvent`）
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/entities/player/player.dart';
import 'channel_player.dart';
import 'player_channel_bridge.dart';

/// 播放器控制层。
class PlayerController {
  PlayerController({
    required PlayerChannelBridge bridge,
    required List<PlayerBackend> backendChain,
    required PlayerBackend Function(PlayerSource source) selectInitialBackend,
  })  : _bridge = bridge,
        _backendChain = List<PlayerBackend>.unmodifiable(backendChain),
        _selectInitialBackend = selectInitialBackend;

  final PlayerChannelBridge _bridge;
  final List<PlayerBackend> _backendChain;
  final PlayerBackend Function(PlayerSource source) _selectInitialBackend;

  static PlayerController? _instance;

  /// 全局实例（app 启动接线；测试用 [overrideForTest] 注入假实现）。
  static PlayerController get instance =>
      _instance ??= _createDefault();

  @visibleForTesting
  static void overrideForTest(PlayerController controller) {
    _instance = controller;
  }

  static PlayerController _createDefault() {
    final List<PlayerBackend> chain =
        PlayerBackendSelector.chainFor(Platform.operatingSystem);
    return PlayerController(
      bridge: MethodChannelPlayerBridge(),
      backendChain: chain,
      selectInitialBackend: (PlayerSource source) =>
          PlayerBackendSelector.needsFallback(source.url) &&
                  chain.contains(PlayerBackend.libVLC)
              ? PlayerBackend.libVLC
              : chain.first,
    );
  }

  ChannelPlayer? _player;
  PlayerState? _state;

  /// 当前播放器（未 open 为 null）。
  Player? get player => _player;

  /// 当前后端（未 open 为 null）。
  PlayerBackend? get backend => _player?.backend;

  /// 最近状态。
  PlayerState? get state => _state;

  void Function(PlayerState)? onStateChanged;

  void Function(PlaybackProgress)? onProgress;

  void Function(String message, {required bool fatal})? onError;

  // ─────────────── 控制面 ───────────────

  /// 打开媒体：按后端降级链逐个尝试（失败回退下一后端）。
  Future<void> open(PlayerSource source) async {
    await _disposePlayer();
    PlayerOpenException? last;
    for (final PlayerBackend backend in _orderedChain(source)) {
      final ChannelPlayer p = ChannelPlayer(backend: backend, bridge: _bridge);
      _attach(p);
      _player = p;
      try {
        await p.open(source);
        _state = PlayerState.opening;
        onStateChanged?.call(_state!);
        return;
      } on PlayerOpenException catch (e) {
        last = e;
        onError?.call('后端 ${backend.name} 打开失败：${e.message}', fatal: true);
        await _disposePlayer();
      }
    }
    throw last ??
        const PlayerOpenException('E_NO_BACKEND', '无可用播放后端');
  }

  Future<void> play() async {
    if (_player == null) return;
    await _player!.play();
  }

  Future<void> pause() async {
    if (_player == null) return;
    await _player!.pause();
  }

  /// 播放 / 暂停切换（文档 T.7 `PlayPauseIntent` 接线目标）。
  Future<void> togglePlay() async {
    final PlayerState? s = _state;
    if (s == PlayerState.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seekTo(int positionMs) async {
    if (_player == null) return;
    await _player!.seekTo(positionMs);
  }

  Future<void> setVolume(double volume) async {
    if (_player == null) return;
    await _player!.setVolume(volume);
  }

  Future<void> setSpeed(double speed) async {
    if (_player == null) return;
    await _player!.setSpeed(speed);
  }

  /// 释放播放器 + 桥资源。
  Future<void> dispose() async {
    await _disposePlayer();
    await _bridge.dispose();
  }

  // ─────────────── 内部 ───────────────

  List<PlayerBackend> _orderedChain(PlayerSource source) {
    final PlayerBackend initial = _selectInitialBackend(source);
    return <PlayerBackend>[
      initial,
      ..._backendChain.where((PlayerBackend b) => b != initial),
    ];
  }

  void _attach(ChannelPlayer p) {
    p.onStateChanged = (PlayerState s) {
      _state = s;
      onStateChanged?.call(s);
    };
    p.onProgress = onProgress;
    p.onError = onError;
  }

  Future<void> _disposePlayer() async {
    final ChannelPlayer? p = _player;
    _player = null;
    _state = null;
    if (p != null) {
      await p.dispose();
    }
  }
}
