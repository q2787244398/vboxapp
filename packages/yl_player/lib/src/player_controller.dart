import 'dart:async';

import 'package:flutter/services.dart';

import 'models.dart';

/// Platform channel used by the yl_player plugin.
const MethodChannel _kYlChannel =
    MethodChannel('dev.flutter.pigeon.yl_player');

/// Drives a single yl_player session.
///
/// The Pigeon-generated methods (`load`, `play`, ... on the host API and
/// `onState`, `onFirstFrame`, ... on the Flutter API) are wired in the
/// platform plugins; this controller is the Dart-facing facade the app uses.
class YlPlayerController {
  final int _id;
  final YlPlayerOptions _options;

  PlayerStatus _status = PlayerStatus.idle;
  String? _error;

  final _statusController =
      StreamController<PlayerStatus>.broadcast();
  final _deltaController =
      StreamController<PlayerStateDelta>.broadcast();
  final _firstFrameController = StreamController<void>.broadcast();
  final _engineController = StreamController<String>.broadcast();

  YlPlayerController(this._id, this._options) {
    _registerListeners();
  }

  PlayerStatus get status => _status;
  String? get error => _error;

  Stream<PlayerStatus> get onStatus => _statusController.stream;
  Stream<PlayerStateDelta> get onStateDelta => _deltaController.stream;
  Stream<void> get onFirstFrame => _firstFrameController.stream;
  Stream<String> get onEngineChanged => _engineController.stream;

  // ----- Host API (Dart -> native) -----

  Future<void> load(YlSource source) async {
    _status = PlayerStatus.loading;
    await _invoke('load', {
      'id': _id,
      'kind': source.kind.index,
      'url': source.url,
      'autoplay': _options.autoplay,
      'decoderPolicy': _options.decoderPolicy.index,
      'maxWidth': _options.maxWidth,
      'maxHeight': _options.maxHeight,
    });
  }

  Future<void> play() => _invoke('play', {'id': _id});

  Future<void> pause() => _invoke('pause', {'id': _id});

  Future<void> stop() async {
    _status = PlayerStatus.idle;
    await _invoke('stop', {'id': _id});
  }

  Future<void> seekTo(int positionMs) =>
      _invoke('seekTo', {'id': _id, 'positionMs': positionMs});

  Future<void> seekToLiveEdge() => _invoke('seekToLiveEdge', {'id': _id});

  Future<void> setVolume(double volume) =>
      _invoke('setVolume', {'id': _id, 'volume': volume});

  Future<void> setPlaybackSpeed(double speed) =>
      _invoke('setPlaybackSpeed', {'id': _id, 'speed': speed});

  Future<void> selectAudioTrack(int index) =>
      _invoke('selectAudioTrack', {'id': _id, 'index': index});

  Future<void> attach(int surfaceId) =>
      _invoke('attach', {'id': _id, 'surfaceId': surfaceId});

  Future<List<YlAudioTrack>> assess() async {
    final raw = await _invoke('assess', {'id': _id});
    if (raw is Map && raw['tracks'] is List) {
      return (raw['tracks'] as List)
          .whereType<Map>()
          .map((t) => YlAudioTrack(
                t['index'] as int,
                language: t['language'] as String?,
                title: t['title'] as String?,
              ))
          .toList();
    }
    return [];
  }

  Future<void> dispose() async {
    await _invoke('dispose', {'id': _id});
    await _dispose();
  }

  Future<dynamic> _invoke(String method, Map<String, dynamic> args) async {
    try {
      return await _kYlChannel.invokeMethod(method, args);
    } on PlatformException catch (e) {
      _error = e.message;
      _status = PlayerStatus.error;
      rethrow;
    }
  }

  // ----- Flutter API callbacks (native -> Dart) -----

  void _registerListeners() {
    try {
      _kYlChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onState':
            _status =
                PlayerStatus.values[call.arguments as int];
            _statusController.add(_status);
            break;
          case 'onStateDelta':
            final delta = PlayerStateDelta(
              positionMs: call.arguments['positionMs'] as int,
              durationMs: call.arguments['durationMs'] as int,
              liveEdgeMs: call.arguments['liveEdgeMs'] as int? ?? 0,
              speed: call.arguments['speed'] as double? ?? 1.0,
              volume: call.arguments['volume'] as double? ?? 1.0,
            );
            _deltaController.add(delta);
            break;
          case 'onFirstFrame':
            _firstFrameController.add(null);
            break;
          case 'onPlaybackFailed':
            _error = call.arguments as String?;
            _status = PlayerStatus.error;
            _statusController.add(_status);
            break;
          case 'onRetryScheduled':
            break;
          case 'onEngineChanged':
            _engineController.add(call.arguments as String);
            break;
        }
        return null;
      });
    } catch (_) {
      // Platform view may not be available (e.g., web fallback).
    }
  }

  Future<void> _dispose() async {
    await _statusController.close();
    await _deltaController.close();
    await _firstFrameController.close();
    await _engineController.close();
  }
}
