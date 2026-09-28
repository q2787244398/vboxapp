import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';

/// Grid widget for displaying video cards.
class VideoGrid extends StatelessWidget {
  final List<Vod> videos;
  final ValueChanged<Vod> onVideoTap;
  final int crossAxisCount;

  const VideoGrid({
    super.key,
    required this.videos,
    required this.onVideoTap,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '暂无内容',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.65,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final vod = videos[index];
            return VideoCard(vod: vod, onTap: () => onVideoTap(vod));
          },
          childCount: videos.length,
        ),
      ),
    );
  }
}

/// Individual video card.
class VideoCard extends StatelessWidget {
  final Vod vod;
  final VoidCallback onTap;

  const VideoCard({super.key, required this.vod, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: vod.name,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
              onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: vod.pic != null
                        ? DecorationImage(
                            image: NetworkImage(vod.pic!),
                            fit: BoxFit.cover,
                            colorFilter:
                                const ColorFilter.mode(Colors.black26, BlendMode.darken),
                          )
                        : null,
                    color: vod.pic == null ? Colors.white.withValues(alpha: 0.06) : null,
                  ),
                  child: vod.pic == null
                      ? const Icon(Icons.video_library, color: Colors.white30)
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                vod.name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (vod.remarks != null && vod.remarks!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    vod.remarks!,
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
