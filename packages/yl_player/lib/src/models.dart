/// Data models for the yl_player plugin.
///
/// These mirror the Pigeon message types observed in the shipped Android
/// binary (AndroidSourceMessage, AndroidPlayerOptionsMessage, ...) — kept
/// platform-neutral here so the same Dart surface drives Android / Apple /
/// Windows backends.

/// Playback state machine (matches AndroidPlayerStatus / native).
enum PlayerStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  ended,
  error,
}

/// Which source kind a YlSource represents.
enum YlSourceKind { url, byteStream, local, live }

/// A source the player can load.
class YlSource {
  final YlSourceKind kind;
  final String? url;
  final List<int>? bytes;

  const YlSource.url(this.url)
      : kind = YlSourceKind.url,
        bytes = null;

  const YlSource.bytes(this.bytes)
      : kind = YlSourceKind.byteStream,
        url = null;

  const YlSource.local(String path)
      : kind = YlSourceKind.local,
        url = path,
        bytes = null;

  const YlSource.live(this.url)
      : kind = YlSourceKind.live,
        bytes = null;
}

/// Selectable audio track.
class YlAudioTrack {
  final int index;
  final String? language;
  final String? title;

  const YlAudioTrack(this.index, {this.language, this.title});
}

/// Decoder preference.
enum YlDecodePolicy { auto, hardware, software }

/// Options for creating a player session.
class YlPlayerOptions {
  final bool autoplay;
  final YlDecodePolicy decoderPolicy;
  final int? maxWidth;
  final int? maxHeight;

  const YlPlayerOptions({
    this.autoplay = false,
    this.decoderPolicy = YlDecodePolicy.auto,
    this.maxWidth,
    this.maxHeight,
  });
}

/// Periodic state deltas pushed by the engine (onStateDelta).
class PlayerStateDelta {
  final int positionMs;
  final int durationMs;
  final int liveEdgeMs;
  final double speed;
  final double volume;

  const PlayerStateDelta({
    this.positionMs = 0,
    this.durationMs = 0,
    this.liveEdgeMs = 0,
    this.speed = 1.0,
    this.volume = 1.0,
  });
}
