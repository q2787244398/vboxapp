import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';

/// Video playback state, mirrored from the yl_player platform plugin.
enum PlayerStateType { idle, loading, playing, paused, ended, error }

/// Service for video playback control.
///
/// On mobile this delegates to the yl_player platform plugin (MediaCodec /
/// AVPlayer + VideoToolbox backends). State changes flow back through the
/// Pigeon callbacks and are reflected here so the UI can react.
class PlayerService with ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('dev.flutter.pigeon.yl_player_android');

  PlayerStateType _state = PlayerStateType.idle;
  String? _currentUrl;
  Vod? _currentVod;
  List<PlaySource> _playSources = [];
  int _selectedSourceIndex = 0;
  int _selectedEpisodeIndex = 0;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _isMuted = false;
  bool _isFullscreen = false;
  String? _error;

  // Getters
  PlayerStateType get state => _state;
  String? get currentUrl => _currentUrl;
  Vod? get currentVod => _currentVod;
  List<PlaySource> get playSources => _playSources;
  int get selectedSourceIndex => _selectedSourceIndex;
  int get selectedEpisodeIndex => _selectedEpisodeIndex;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  bool get isMuted => _isMuted;
  bool get isFullscreen => _isFullscreen;
  String? get error => _error;

  /// Load and play a video.
  Future<void> play(
    String url, {
    Vod? vod,
    List<PlaySource>? playSources,
    int sourceIndex = 0,
    int episodeIndex = 0,
  }) async {
    _currentUrl = url;
    _currentVod = vod;
    _playSources = playSources ?? [];
    _selectedSourceIndex = sourceIndex;
    _selectedEpisodeIndex = episodeIndex;
    _state = PlayerStateType.loading;
    _error = null;
    _positionMs = 0;
    _durationMs = 0;
    notifyListeners();
  }

  /// Internal helper: switch to another url while keeping the current vod
  /// and source list. Mirrors [play] without resetting the selection indices.
  Future<void> _playUrl(
    String url, {
    Vod? vod,
    List<PlaySource>? playSources,
  }) async {
    _currentUrl = url;
    if (vod != null) _currentVod = vod;
    if (playSources != null) _playSources = playSources;
    _state = PlayerStateType.loading;
    _error = null;
    _positionMs = 0;
    _durationMs = 0;
    notifyListeners();
  }

  void pause() {
    if (_state == PlayerStateType.playing) {
      _state = PlayerStateType.paused;
      notifyListeners();
    }
  }

  void resume() {
    if (_state == PlayerStateType.paused) {
      _state = PlayerStateType.playing;
      notifyListeners();
    }
  }

  void stop() {
    _state = PlayerStateType.idle;
    _currentUrl = null;
    _currentVod = null;
    _playSources = [];
    _selectedSourceIndex = 0;
    _selectedEpisodeIndex = 0;
    _positionMs = 0;
    _durationMs = 0;
    _error = null;
    notifyListeners();
  }

  void seekTo(int positionMs) {
    _positionMs = positionMs;
    notifyListeners();
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    notifyListeners();
  }

  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    notifyListeners();
  }

  void selectSource(int index) {
    if (index < 0 || index >= _playSources.length) return;
    _selectedSourceIndex = index;
    _selectedEpisodeIndex = 0;
    final source = _playSources[index];
    _playUrl(source.list[0].url, vod: _currentVod, playSources: _playSources);
  }

  void selectEpisode(int index) {
    if (index < 0 ||
        index >= _playSources[_selectedSourceIndex].list.length) {
      return;
    }
    _selectedEpisodeIndex = index;
    final source = _playSources[_selectedSourceIndex];
    _playUrl(source.list[index].url, vod: _currentVod, playSources: _playSources);
  }

  // ----- platform callbacks (from Pigeon) -----
  void handleStateChanged(PlayerStateType state, {String? error}) {
    _state = state;
    if (error != null) _error = error;
    notifyListeners();
  }

  void handlePosition(int positionMs, int durationMs) {
    _positionMs = positionMs;
    _durationMs = durationMs;
    notifyListeners();
  }
}
