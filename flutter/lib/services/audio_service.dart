import 'package:flutter/material.dart';

/// Background audio playback state (podcast / audiobook player).
///
/// Backed by the audio_service plugin on device; this model exposes the
/// state surface the UI needs. Playback is started with a URL plus metadata.
class AudioService with ChangeNotifier {
  bool _isPlaying = false;
  String? _currentUrl;
  String? _currentTitle;
  String? _currentArtist;
  String? _currentArtwork;
  int _positionMs = 0;
  int _durationMs = 0;
  double _playbackSpeed = 1.0;

  bool get isPlaying => _isPlaying;
  String? get currentUrl => _currentUrl;
  String? get currentTitle => _currentTitle;
  String? get currentArtist => _currentArtist;
  String? get currentArtwork => _currentArtwork;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  double get playbackSpeed => _playbackSpeed;

  Future<void> play(String url,
      {String? title, String? artist, String? artwork}) async {
    _currentUrl = url;
    _currentTitle = title;
    _currentArtist = artist;
    _currentArtwork = artwork;
    _isPlaying = true;
    _positionMs = 0;
    notifyListeners();
  }

  void pause() {
    _isPlaying = false;
    notifyListeners();
  }

  void resume() {
    if (_currentUrl != null) {
      _isPlaying = true;
      notifyListeners();
    }
  }

  void stop() {
    _isPlaying = false;
    _currentUrl = null;
    _currentTitle = null;
    _currentArtist = null;
    _currentArtwork = null;
    _positionMs = 0;
    _durationMs = 0;
    notifyListeners();
  }

  void seekTo(int positionMs) {
    _positionMs = positionMs;
    notifyListeners();
  }

  void setDuration(int durationMs) {
    _durationMs = durationMs;
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    notifyListeners();
  }

  /// Update position called periodically by the platform engine.
  void updatePosition(int positionMs, int durationMs) {
    _positionMs = positionMs;
    _durationMs = durationMs;
    notifyListeners();
  }
}
