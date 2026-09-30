/// 详情页：详情信息 + 线路/剧集选择 + 播放入口（收藏/历史条目接线目标）。
///
/// 数据通路：收藏/历史条目（siteKey + vodId + initialIndex）→ [DetailPlaybackUseCases]
/// → 详情内容（PlaybackDetail）→ 单集 `playerContent` 解析 → [PlayerController] 播放。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/player/player.dart';
import '../../domain/entities/playback/playback.dart';
import '../../domain/entities/spider/spider_models.dart';
import '../../domain/usecases/usecases.dart';
import '../../platform/player/player_controller.dart';

/// 详情页。
class DetailPage extends StatefulWidget {
  /// 构造。
  const DetailPage({
    super.key,
    required this.siteKey,
    required this.vodId,
    this.initialIndex = 0,
    this.title,
  });

  /// 站点 key（收藏/历史条目的 laiyuan）。
  final String siteKey;

  /// 影片 ID（收藏/历史条目的 detailurl）。
  final String vodId;

  /// 默认选中的剧集索引（历史续播入口；钳制到合法区间）。
  final int initialIndex;

  /// 页面标题（缺省用详情名）。
  final String? title;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final DetailPlaybackUseCases _uc;
  PlaybackDetail? _detail;
  Failure? _error;
  bool _loaded = false;
  bool _playing = false;
  int _fromIndex = 0;
  int _episodeIndex = 0;

  @override
  void initState() {
    super.initState();
    // 用例引用在 initState 缓存，避免跨 async gap 使用 context
    _uc = context.read<DetailPlaybackUseCases>();
    _load();
  }

  Future<void> _load() async {
    final Result<PlaybackDetail> result = await _uc.loadDetail(
      siteKey: widget.siteKey,
      vodId: widget.vodId,
      initialIndex: widget.initialIndex,
    );
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _error = result.failureOrNull;
      _detail = result.valueOrNull;
    });
    _applyInitialSelection();
  }

  /// 初始剧集索引 → 线路索引 + 线路内剧集索引。
  void _applyInitialSelection() {
    final PlaybackDetail? d = _detail;
    if (d == null) return;
    if (d.froms.isEmpty || d.episodes.isEmpty) {
      _fromIndex = 0;
      _episodeIndex = d.initialIndex;
      return;
    }
    final int flat = d.initialIndex.clamp(0, d.episodes.length - 1);
    final PlaybackEpisode target = d.episodes[flat];
    final int line = d.froms.indexOf(target.from ?? '');
    final int fromIdx = line < 0 ? 0 : line;
    final List<PlaybackEpisode> visible = _episodesForLine(fromIdx);
    _fromIndex = fromIdx;
    _episodeIndex = visible.indexWhere(
      (PlaybackEpisode e) => e.url == target.url && e.name == target.name,
    );
    if (_episodeIndex < 0) _episodeIndex = 0;
  }

  /// 指定线路的剧集（无线路信息时返回全集）。
  List<PlaybackEpisode> _episodesForLine(int lineIndex) {
    final PlaybackDetail? d = _detail;
    if (d == null) return const <PlaybackEpisode>[];
    if (d.froms.isEmpty) return d.episodes;
    final String from =
        d.froms[lineIndex.clamp(0, d.froms.length - 1)];
    final List<PlaybackEpisode> out = d.episodes
        .where((PlaybackEpisode e) => e.from == from)
        .toList();
    return out.isEmpty ? d.episodes : out;
  }

  Future<void> _play() async {
    final PlaybackDetail? d = _detail;
    if (d == null || _playing) return;
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    if (visible.isEmpty) return;
    final PlaybackEpisode episode =
        visible[_episodeIndex.clamp(0, visible.length - 1)];

    setState(() => _playing = true);
    try {
      final Result<PlayerContentResult> result =
          await _uc.resolvePlayUrl(detail: d, episode: episode);
      if (!mounted) return;
      final Failure? failure = result.failureOrNull;
      if (failure != null) {
        _toast('解析失败：$failure');
        return;
      }
      final PlayerContentResult? pc = result.valueOrNull;
      final String? url = _firstUrl(pc);
      if (url == null || url.isEmpty) {
        _toast('未解析到播放地址');
        return;
      }

      final PlayerController controller = PlayerController.instance;
      await controller.open(
        PlayerSource(
          url: url,
          title: episode.name.isEmpty
              ? d.vod.vodName
              : '${d.vod.vodName} - ${episode.name}',
          headers: pc?.header ?? const <String, String>{},
        ),
      );
      await controller.play();
      if (!mounted) return;
      _toast('开始播放：${episode.name}');
    } catch (e) {
      if (!mounted) return;
      _toast('播放失败：$e');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  String? _firstUrl(PlayerContentResult? pc) {
    if (pc == null) return null;
    final String? u = pc.url;
    if (u != null && u.isNotEmpty) return u;
    if (pc.urls != null && pc.urls!.isNotEmpty) return pc.urls!.first;
    final String? pu = pc.playUrl;
    if (pu != null && pu.isNotEmpty) return pu;
    return null;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─────────────── UI ───────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? _detail?.vod.vodName ?? '详情')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final Failure? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _retry);
    }
    final PlaybackDetail? d = _detail;
    if (d == null) {
      return const Center(child: Text('详情为空'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildHeader(d),
        const SizedBox(height: 16),
        _buildLineSelector(d),
        const SizedBox(height: 8),
        _buildEpisodes(d),
        const SizedBox(height: 16),
        _buildPlayButton(),
      ],
    );
  }

  void _retry() {
    setState(() {
      _loaded = false;
      _error = null;
      _detail = null;
    });
    _load();
  }

  Widget _buildHeader(PlaybackDetail d) {
    final VodItem vod = d.vod;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 120,
            height: 160,
            child: vod.vodPic.isEmpty
                ? Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.movie_outlined, size: 48),
                  )
                : Image.network(
                    vod.vodPic,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (BuildContext context, Object error, StackTrace? stack) =>
                            Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.movie_outlined, size: 48),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                vod.vodName,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (vod.vodYear?.isNotEmpty ?? false) vod.vodYear!,
                  if (vod.vodArea?.isNotEmpty ?? false) vod.vodArea!,
                  if (vod.vodRemarks?.isNotEmpty ?? false) vod.vodRemarks!,
                ].join(' / '),
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if ((vod.vodActor?.isNotEmpty ?? false) ||
                  (vod.vodDirector?.isNotEmpty ?? false)) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  [
                    if (vod.vodDirector?.isNotEmpty ?? false)
                      '导演：${vod.vodDirector}',
                    if (vod.vodActor?.isNotEmpty ?? false) '主演：${vod.vodActor}',
                  ].join('\n'),
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLineSelector(PlaybackDetail d) {
    if (d.froms.length <= 1) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        for (int i = 0; i < d.froms.length; i++)
          ChoiceChip(
            label: Text(d.froms[i]),
            selected: i == _fromIndex,
            onSelected: (bool selected) {
              if (!selected) return;
              setState(() {
                _fromIndex = i;
                _episodeIndex = 0;
              });
            },
          ),
      ],
    );
  }

  Widget _buildEpisodes(PlaybackDetail d) {
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    if (visible.isEmpty) {
      return const Text('暂无剧集');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int i = 0; i < visible.length; i++)
          ActionChip(
            avatar: i == _episodeIndex ? const Icon(Icons.play_arrow, size: 16) : null,
            label: Text(visible[i].name.isEmpty ? '第${i + 1}集' : visible[i].name),
            backgroundColor: i == _episodeIndex
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            onPressed: () {
              setState(() => _episodeIndex = i);
              _play();
            },
          ),
      ],
    );
  }

  Widget _buildPlayButton() {
    final PlaybackDetail? d = _detail;
    final bool enabled = d != null && _episodesForLine(_fromIndex).isNotEmpty;
    return FilledButton.icon(
      onPressed: _playing || !enabled ? null : _play,
      icon: _playing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow),
      label: Text(_playing ? '播放中…' : '播放'),
    );
  }
}

/// 加载失败提示 + 重试。
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
