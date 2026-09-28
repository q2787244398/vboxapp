import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import '../services/node_service.dart';

/// Video detail page with episode selection and play button.
class DetailPage extends StatefulWidget {
  final String siteKey;
  final String vodId;
  final Vod? initialVod;

  const DetailPage({
    super.key,
    required this.siteKey,
    required this.vodId,
    this.initialVod,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Vod? _vod;
  Map<String, dynamic>? _detail;
  List<PlaySource> _playSources = [];
  int _selectedSourceIndex = 0;
  int _selectedEpisodeIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final nodeService = context.read<NodeService>();
    setState(() {
      _isLoading = true;
      _vod = widget.initialVod;
    });

    try {
      if (siteKey == '' && widget.initialVod == null) {
        // No site — just show the initial vod if we have it
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final detail = await nodeService.getVideoDetail(
        siteKey.isNotEmpty ? siteKey : (widget.initialVod?.siteKey ?? ''),
        widget.vodId,
      );

      if (!mounted) return;

      final vod = Vod.fromJson({
        ...?widget.initialVod?.toJson(),
        ...detail,
      });

      final sources = (detail['list'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(PlaySource.fromJson)
              .toList() ??
          [];

      // Record in watch history
      await context.read<DatabaseService>().addWatchHistory(vod);

      setState(() {
        _vod = vod;
        _detail = detail;
        _playSources = sources;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  String get siteKey => widget.siteKey;

  void _onPlayTap() {
    if (_playSources.isEmpty) return;

    final source = _playSources[_selectedSourceIndex];
    if (source.list.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可用的播放链接')));
      return;
    }
    // Hand off the current selection; the player page resolves the final
    // play URL (episode URL directly, playUrl API preferred).
    context.go('/player', extra: _vod ?? widget.initialVod);
  }

  Vod? get vod => _vod ?? widget.initialVod;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final vod = _vod ?? widget.initialVod;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: vod?.pic != null ? 240 : 120,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                vod?.name ?? '详情',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              background: vod?.pic != null
                  ? Image.network(
                      vod!.pic!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, e, stack) => Container(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                    )
                  : Container(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vod != null) ...[
                    Text(vod.name,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (vod.year != null) _chip(vod.year!),
                        if (vod.area != null) _chip(vod.area!),
                        if (vod.tag != null) _chip(vod.tag!),
                        if (vod.remarks != null) _chip(vod.remarks!),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_detail != null &&
                      (_detail!['vod_content'] as String? ?? '').isNotEmpty) ...[
                    Text(
                      _detail!['vod_content'],
                      style: const TextStyle(color: Colors.white70, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_playSources.isNotEmpty) ...[
                    const Text('选集',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _playSources.length,
                        itemBuilder: (context, index) {
                          final source = _playSources[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              selected: index == _selectedSourceIndex,
                              label: Text(
                                  '${source.from}（${source.list.length}集）'),
                              onSelected: (_) {
                                setState(() {
                                  _selectedSourceIndex = index;
                                  _selectedEpisodeIndex = 0;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _playSources[_selectedSourceIndex].list
                          .asMap()
                          .entries
                          .map((entry) {
                        final index = entry.key;
                        final episode = entry.value;
                        final isSelected = index == _selectedEpisodeIndex;
                        return ActionChip(
                          label: Text(
                            episode.name,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF58A6FF)
                                  : Colors.white70,
                            ),
                          ),
                          backgroundColor: isSelected
                              ? const Color(0xFF1F6FEB).withValues(alpha: 0.25)
                              : null,
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFF58A6FF)
                                : Colors.white24,
                          ),
                          onPressed: () =>
                              setState(() => _selectedEpisodeIndex = index),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _playSources.isNotEmpty ? _onPlayTap : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('播放',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    );
  }
}
