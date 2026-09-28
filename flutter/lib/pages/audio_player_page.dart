import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_service.dart';

/// Background audio player page (podcasts / audiobooks).
class AudioPlayerPage extends StatefulWidget {
  const AudioPlayerPage({super.key});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, audio, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('音频'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.favorite_border),
                onPressed: () {},
              ),
            ],
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Album art
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    image: audio.currentArtwork != null
                        ? DecorationImage(
                            image: NetworkImage(audio.currentArtwork!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: audio.currentArtwork == null
                      ? const Icon(Icons.audiotrack, size: 64, color: Colors.white30)
                      : null,
                ),
                const SizedBox(height: 24),
                Text(
                  audio.currentTitle ?? '未在播放',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  audio.currentArtist ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 24),
                // Progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Slider(
                        value: audio.durationMs > 0
                            ? (audio.positionMs / audio.durationMs).clamp(0.0, 1.0)
                            : 0.0,
                        onChanged: audio.durationMs > 0
                            ? (v) => audio.seekTo((v * audio.durationMs).toInt())
                            : null,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(audio.positionMs),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            _formatDuration(audio.durationMs),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Transport controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous,
                          color: Colors.white, size: 32),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        audio.isPlaying
                            ? Icons.pause_circle
                            : Icons.play_circle,
                        color: Colors.white,
                        size: 64,
                      ),
                      onPressed:
                          audio.isPlaying ? audio.pause : () => audio.resume(),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.skip_next,
                          color: Colors.white, size: 32),
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Speed
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${audio.playbackSpeed}×',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    IconButton(
                      icon: const Icon(Icons.speed, size: 20, color: Colors.white54),
                      onPressed: () => _pickSpeed(context, audio),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _pickSpeed(BuildContext context, AudioService audio) {
    final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('倍速'),
        children: [
          for (final s in speeds)
            SimpleDialogOption(
              onPressed: () {
                audio.setPlaybackSpeed(s);
                Navigator.pop(context);
              },
              child: Text('${s}×'),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    if (hours > 0) {
      return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    }
    return '${minutes}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
