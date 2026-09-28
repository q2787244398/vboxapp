import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:yl_player/yl_player.dart' show YlPlayerView;

import '../models/models.dart';
import '../services/node_service.dart';
import '../services/player_service.dart';

/// Full-screen video player page.
class PlayerPage extends StatefulWidget {
  final Vod? vod;

  const PlayerPage({super.key, this.vod});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  bool _ready = false;
  String? _playError;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final player = context.read<PlayerService>();
    final vod = widget.vod;

    if (vod?.playUrl != null && vod!.playUrl!.isNotEmpty) {
      await player.play(
        vod.playUrl!,
        vod: vod,
        playSources: vod.playSources,
      );
      if (mounted) setState(() => _ready = true);
    } else {
      // Resolve via spider engine when only the vod id is known.
      final node = context.read<NodeService>();
      if (vod?.siteKey != null && vod?.id != null) {
        final url = await node.getPlayUrl(
          vod!.siteKey!,
          vod.id!,
          playFrom: vod.playFrom,
        );
        if (url != null && url.isNotEmpty) {
          await player.play(url, vod: vod, playSources: vod.playSources);
          if (mounted) setState(() => _ready = true);
        } else {
          if (mounted) {
            setState(() {
              _playError = '未能解析播放链接';
              _ready = true;
            });
          }
        }
      }
    }
  }

  @override
  void dispose() {
    // Keep the service alive (supports background audio); just clean local.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerService>(
      builder: (context, player, child) {
        final vod = widget.vod;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              _buildVideoSurface(player, vod),
              Positioned(
                top: 0, left: 0, right: 0,
                child: _buildTopBar(player, vod),
              ),
              if (!_playError case final e when e != null)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: _buildBottomControls(player),
                ),
              if (player.state == PlayerStateType.loading)
                const Center(child: CircularProgressIndicator()),
              if (_playError != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 56, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_playError!,
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.pop(),
                        child: const Text('返回'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoSurface(PlayerService player, Vod? vod) {
    if (player.currentUrl == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('yl_player Video Surface',
              style: TextStyle(color: Colors.white30)),
        ),
      );
    }
    // The plugin registers a platform-view surface (a MediaCodec /
    // VideoToolbox rendered texture) that the engine drives.
    return IgnorePointer(
      child: Container(
        color: Colors.black,
        child: YlPlayerView(surfaceId: _surfaceId),
      ),
    );
  }

  static const int _surfaceId = 1;

  Widget _buildTopBar(PlayerService player, Vod? vod) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black.withOpacity(0.65), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  vod?.name ?? '播放中',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  player.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: player.toggleFullscreen,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(PlayerService player) {
    final sources = player.playSources;
    final episodeCount =
        sources.isNotEmpty ? sources[player.selectedSourceIndex].list.length : 0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withOpacity(0.65)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Episode progress
              Slider(
                value: player.durationMs > 0
                    ? (player.positionMs / player.durationMs).clamp(0.0, 1.0)
                    : 0.0,
                onChanged: player.durationMs > 0
                    ? (value) => player.seekTo((value * player.durationMs).toInt())
                    : null,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(player.positionMs),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    _formatDuration(player.durationMs),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white, size: 26),
                        onPressed: player.selectedEpisodeIndex > 0
                            ? () => player.selectEpisode(player.selectedEpisodeIndex - 1)
                            : null,
                        tooltip: '上一集',
                      ),
                      if (episodeCount > 0)
                        Text(
                          '${player.selectedEpisodeIndex + 1}/$episodeCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      IconButton(
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white, size: 26),
                        onPressed:
                            player.selectedEpisodeIndex < episodeCount - 1
                                ? () => player.selectEpisode(
                                    player.selectedEpisodeIndex + 1)
                                : null,
                        tooltip: '下一集',
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      player.state == PlayerStateType.playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 40,
                    ),
                    onPressed: player.state == PlayerStateType.playing
                        ? player.pause
                        : player.resume,
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(player.isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white),
                        onPressed: player.toggleMute,
                      ),
                      IconButton(
                        icon: const Icon(Icons.speed, color: Colors.white),
                        onPressed: () => _showSpeedDialog(context, player),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
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

  void _showSpeedDialog(BuildContext context, PlayerService player) {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('播放速度'),
        content: Wrap(
          spacing: 8,
          children: [
            for (final speed in speeds)
              ActionChip(
                label: Text('${speed}×'),
                selected: (speed - player.playbackSpeed).abs() < 0.01,
                onPressed: () {
                  player.setPlaybackSpeed(speed);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
