/// yl_player: cross-platform video playback plugin.
///
/// Pigeon-generated API surface reconstructed from the shipped binaries:
///
/// Host API (Dart -> native):
///   load / play / pause / stop / seekTo / seekToLiveEdge /
///   setVolume / setPlaybackSpeed / selectAudioTrack /
///   attach / assess / dispose
///
/// Flutter API (native -> Dart):
///   onState / onStateDelta / onFirstFrame /
///   onPlaybackFailed / onRetryScheduled / onEngineChanged
library yl_player;

export 'src/models.dart'
    show
        PlayerStatus,
        PlayerStateDelta,
        YlPlayerOptions,
        YlSourceKind,
        YlSource,
        YlAudioTrack,
        YlDecodePolicy;
export 'src/player_controller.dart' show YlPlayerController;
export 'src/platform_surface.dart' show YlPlayerView;
