/// 平台层：播放器统一控制层（映射 iOS `PlayerEngineController`）。
///
/// 职责：
///  - 持有当前播放器实例 + 后端降级链（契约 §2.5 + A21.5 的 Dart 侧语义）
///  - `open` 失败时按链回退（A21.5 selectBackend：复杂封装 / HEVC 无硬解走 libVLC）
///  - 状态 / 进度 / 错误回调转发（对齐 iOS `PlayerEngineState` + `PlayerEngineEvent`）
///  - 批次 C · C-01：路由（影视/直播/网盘/音乐/本地）→ 三端差异化后端选择
///  - 批次 C · C-06：降级可观测（[onBackendFallback] 事件 + debugPrint 日志）
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/entities/player/player.dart';
import 'channel_player.dart';
import 'playback_route.dart';
import 'player_channel_bridge.dart';

/// 播放器控制层。
class PlayerController {
  PlayerController({
    required PlayerChannelBridge bridge,
    required List<PlayerBackend> backendChain,
    required PlayerBackend Function(PlayerSource source, PlaybackRoute route)
        selectInitialBackend,
  })  : _bridge = bridge,
        _backendChain = List<PlayerBackend>.unmodifiable(backendChain),
        _selectInitialBackend = selectInitialBackend;

  final PlayerChannelBridge _bridge;
  final List<PlayerBackend> _backendChain;
  final PlayerBackend Function(PlayerSource source, PlaybackRoute route)
      _selectInitialBackend;

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
      selectInitialBackend: (PlayerSource source, PlaybackRoute route) {
        // 直播 FLV / 复杂封装（MKV/FLV/TS…）需全格式后端 → libVLC 优先（桌面 libmpv 同理）。
        final bool needsFallback =
            PlayerBackendSelector.needsFallback(source.url) ||
                (route == PlaybackRoute.live && _isFlv(source.url));
        if (needsFallback && chain.contains(PlayerBackend.libVLC)) {
          return PlayerBackend.libVLC;
        }
        if (needsFallback && chain.contains(PlayerBackend.libmpv)) {
          return PlayerBackend.libmpv;
        }
        return chain.first;
      },
    );
  }

  /// 是否 FLV 直播/点播流。
  static bool _isFlv(String url) => url.toLowerCase().contains('.flv');

  ChannelPlayer? _player;
  PlayerState? _state;
  PlaybackRoute? _route;

  /// 当前播放器（未 open 为 null）。
  Player? get player => _player;

  /// 当前后端（未 open 为 null）。
  PlayerBackend? get backend => _player?.backend;

  /// 最近状态。
  PlayerState? get state => _state;

  /// 当前播放路由（未 open 为 null；C-01）。
  PlaybackRoute? get route => _route;

  void Function(PlayerState)? onStateChanged;

  void Function(PlaybackProgress)? onProgress;

  /// 后端降级事件（C-06：from → to + 原因；可观测/埋点目标）。
  void Function(PlayerBackend from, PlayerBackend to, String reason)?
      onBackendFallback;

  void Function(String message, {required bool fatal})? _onError;

  void Function(String message, {required bool fatal})? get onError =>
      _onError;

  set onError(void Function(String message, {required bool fatal})? handler) {
    _onError = handler;
    // 已 attach 的播放器同步新处理器（open 之后再设置也生效）。
    _player?.onError = handler;
  }

  // ─────────────── 控制面 ───────────────

  /// 打开媒体：按后端降级链逐个尝试（失败回退下一后端）。
  ///
  /// C-01：打开前先解析播放路由并据此排序后端；C-06：每次回退触发
  /// [onBackendFallback] 事件并写降级日志。
  ///
  /// [route] 为显式路由覆盖（批次 F · F-08 网盘播放：直链特征无法自证 pan 路由，
  /// 由调用方显式传入）；为 null 时按 [PlaybackRouteResolver] 从源推导。
  Future<void> open(PlayerSource source, {PlaybackRoute? route}) async {
    await _disposePlayer();
    final PlaybackRoute resolved = route ?? PlaybackRouteResolver.resolve(source);
    _route = resolved;
    PlayerOpenException? last;
    PlayerBackend? previous;
    for (final PlayerBackend backend in _orderedChain(source, resolved)) {
      if (previous != null) {
        // 上一后端失败，本次尝试即降级：先记降级事件再试新后端（C-06）。
        final String reason = last?.message ?? '';
        debugPrint(
          '[PlayerController] 后端降级：${previous.name} → ${backend.name}'
          '（route=${resolved.name}，$reason）',
        );
        onBackendFallback?.call(previous, backend, reason);
      }
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
      previous = backend;
    }
    _route = null;
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

  /// 释放播放器 + 桥资源（路由一并清空）。
  Future<void> dispose() async {
    await _disposePlayer();
    _route = null;
    await _bridge.dispose();
  }

  // ─────────────── 内部 ───────────────

  List<PlayerBackend> _orderedChain(
    PlayerSource source,
    PlaybackRoute route,
  ) {
    final PlayerBackend initial = _selectInitialBackend(source, route);
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
    p.onError = _onError;
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
