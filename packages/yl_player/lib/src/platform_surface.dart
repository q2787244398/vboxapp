import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-view surface that the native player engine renders into.
///
/// On Android this is a MediaCodec/FFmpeg SurfaceView; on Apple it is a
/// Metal-backed texture driven by AVPlayer/VideoToolbox; on desktop it is a
/// window texture fed by the FFmpeg decoder.
class YlPlayerView extends StatelessWidget {
  final int surfaceId;
  final BoxConstraints? constraints;

  const YlPlayerView({super.key, this.surfaceId = 0, this.constraints});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          constraints ?? const BoxConstraints.expand(),
      child: _Surface(key: ValueKey('yl-player-$surfaceId')),
    );
  }
}

/// Placeholder platform view. The real surface is created by the plugin's
/// platform implementation and keyed by surfaceId.
@immutable
class _Surface extends StatelessWidget {
  final Key? key;

  const _Surface({this.key});

  @override
  Widget build(BuildContext context) {
    // The native plugin registers a texture/platform view under this key.
    // For desktop targets without a registered surface, render a placeholder.
    return ColoredBox(
      color: Colors.black,
      child: const Center(
        child: Text(
          'player surface',
          style: TextStyle(color: Colors.white24, fontSize: 12),
        ),
      ),
    );
  }
}
