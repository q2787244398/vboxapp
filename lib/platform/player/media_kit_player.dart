/// 平台层：media_kit 播放器内核（实现 [Player]）。
///
/// 纯 Dart 直连 media_kit（底层 libmpv，渲染走 ANGLE/D3D11，无真 GPU 时自动落
/// D3D11 WARP 软件光栅化），不经 MethodChannel。替代 Windows/macOS 自研 mpv
/// 渲染桥（OpenGL FBO + libswscale 软渲染，云电脑上「有声无画」）。
library;

import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../../core/utils/logger.dart';
import '../../domain/entities/player/player.dart';
import 'media_kit_profile.dart';

/// media_kit 内核（单后端实例）。
///
/// 一个 [MediaKitPlayer] 绑定 [PlayerBackend.mediaKit]；与 [ChannelPlayer] 一样由
/// [PlayerController] 创建，未来插回多内核时由降级链逐个重开。
class MediaKitPlayer implements Player {
  MediaKitPlayer({required this.backend}) {
    mk.MediaKit.ensureInitialized();
    _mpv = mk.Player();
    _controller = mkv.VideoController(
      _mpv,
      configuration: const mkv.VideoControllerConfiguration(
        // 尝试硬解（Windows d3d11va），失败自动回退软解；渲染走 D3D11/WARP。
        enableHardwareAcceleration: true,
      ),
    );
    _bindStreams();
    _controller.id.addListener(_onTextureId);
  }

  @override
  final PlayerBackend backend;

  late final mk.Player _mpv;
  late final mkv.VideoController _controller;

  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];

  // 进度合并缓存：media_kit 的 position/duration/buffer 独立成流，据此合成
  // [PlaybackProgress]（对齐 ChannelPlayer 的 progress 事件口径）。
  int _positionMs = 0;
  int _durationMs = 0;
  int _bufferedMs = 0;
  int _width = 0;
  int _height = 0;
  bool _isLive = false;

  @override
  int? get textureId => _controller.id.value;

  @override
  List<PlayerBackend> get availableBackends => <PlayerBackend>[backend];

  @override
  void Function(PlayerState)? onStateChanged;

  @override
  void Function(PlaybackProgress)? onProgress;

  @override
  void Function(int width, int height)? onVideoSize;

  @override
  void Function(int textureId)? onTextureReady;

  @override
  void Function(String message, {required bool fatal})? onError;

  // ─────────────── 控制面 ───────────────

  @override
  Future<void> open(PlayerSource source) async {
    _isLive = source.isLive;
    final mk.Media media = mk.Media(
      source.url,
      httpHeaders: source.headers.isEmpty ? null : source.headers,
    );
    await _applyTuning(source);
    await _mpv.open(media, play: false);
  }

  @override
  Future<void> play() => _mpv.play();

  @override
  Future<void> pause() => _mpv.pause();

  @override
  Future<void> seekTo(int positionMs) =>
      _mpv.seek(Duration(milliseconds: positionMs));

  /// [Player.setVolume] 契约是 0.0 ~ 1.0，media_kit 的 [mk.Player.setVolume] 是
  /// 0.0 ~ 100.0，此处转换。
  @override
  Future<void> setVolume(double volume) =>
      _mpv.setVolume((volume * 100.0).clamp(0.0, 100.0).toDouble());

  @override
  Future<void> setSpeed(double speed) => _mpv.setRate(speed);

  @override
  Future<void> dispose() async {
    _controller.id.removeListener(_onTextureId);
    for (final StreamSubscription<Object?> s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _mpv.dispose();
  }

  // ─────────────── 调优 ───────────────

  /// 对齐 uz 逆向下发的 libmpv 起播调优（hr-seek + demuxer 缓存）。
  Future<void> _applyTuning(PlayerSource source) async {
    final mk.PlatformPlayer? platform = _mpv.platform;
    if (platform is! mk.NativePlayer) return;
    final MediaKitProfile profile = MediaKitProfile.forSource(source);
    await platform.setProperty('hr-seek', 'yes');
    await platform.setProperty(
      'demuxer-max-bytes',
      profile.demuxerMaxBytes.toString(),
    );
    await platform.setProperty(
      'demuxer-readahead-secs',
      profile.demuxerReadaheadSecs.toString(),
    );
  }

  // ─────────────── 事件面 ───────────────

  void _bindStreams() {
    _subs.add(_mpv.stream.playing.listen((bool playing) {
      onStateChanged?.call(playing ? PlayerState.playing : PlayerState.paused);
    }));
    _subs.add(_mpv.stream.buffering.listen((bool buffering) {
      if (buffering) onStateChanged?.call(PlayerState.buffering);
    }));
    _subs.add(_mpv.stream.completed.listen((bool completed) {
      if (completed) onStateChanged?.call(PlayerState.ended);
    }));
    _subs.add(_mpv.stream.position.listen((Duration d) {
      _positionMs = d.inMilliseconds;
      _emitProgress();
    }));
    _subs.add(_mpv.stream.duration.listen((Duration d) {
      _durationMs = d.inMilliseconds;
      _emitProgress();
    }));
    _subs.add(_mpv.stream.buffer.listen((Duration d) {
      _bufferedMs = d.inMilliseconds;
      _emitProgress();
    }));
    _subs.add(_mpv.stream.width.listen((int? w) {
      if (w != null) _width = w;
      _emitVideoSize();
    }));
    _subs.add(_mpv.stream.height.listen((int? h) {
      if (h != null) _height = h;
      _emitVideoSize();
    }));
    _subs.add(_mpv.stream.error.listen((String message) {
      onError?.call(message, fatal: true);
    }));
    _subs.add(_mpv.stream.log.listen(_log));
  }

  void _emitProgress() {
    onProgress?.call(PlaybackProgress(
      positionMs: _positionMs,
      durationMs: _durationMs,
      bufferedMs: _bufferedMs,
      isLive: _isLive,
    ));
  }

  void _emitVideoSize() {
    if (_width > 0 && _height > 0) {
      onVideoSize?.call(_width, _height);
    }
  }

  void _onTextureId() {
    final int? id = _controller.id.value;
    if (id != null && id >= 0) {
      onTextureReady?.call(id);
    }
  }

  void _log(mk.PlayerLog log) {
    if (log.text.isEmpty) return;
    switch (log.level) {
      case 'error':
      case 'fatal':
        AppLog.error('player-media_kit', log.text, category: LogCategory.player);
        return;
      case 'warn':
      case 'warning':
        AppLog.warn('player-media_kit', log.text, category: LogCategory.player);
        return;
      case 'v':
      case 'debug':
      case 'trace':
        AppLog.debug('player-media_kit', log.text, category: LogCategory.player);
        return;
      default:
        AppLog.info('player-media_kit', log.text, category: LogCategory.player);
    }
  }
}