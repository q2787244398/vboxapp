/// 详情页：头图 + 元信息 + 线路/剧集宫格 + 播放入口（收藏/历史/短剧选集接线目标）。
///
/// 对齐 iOS `VideoDetailView`（`vbox/Views/PlayerViews.swift`）：
/// - 头图封面 + 元信息（备注 / 年份 / 地区 / 导演 / 主演）；
/// - 剧情简介（超长可展开）；
/// - 演职人员（导演 / 主演 chips 横滑；G-06 TMDB 有则整体替换豆瓣）；
/// - 线路 chips（`vod_play_from` 拆分）横滑切源；
/// - 剧集宫格（自适应列数 + 折叠/展开）+ 单集点击选中；
/// - 「立即播放」解析单集播放地址后进入全屏播放页 [PlayerPage]（Wave A · R-渲2）；
/// - 「下载」弹出选集多选 sheet（含全选），确认后解析直链并交
///   [DownloadManager] 入队下载（G-02 接线，对齐 iOS `handleBatchDownload`）。
///
/// 数据通路：[DetailPlaybackUseCases].loadDetail / resolvePlayUrl；
/// 封面 / 演职增强：[TmdbUseCases].enrich（G-06，未启用或未命中时回退站点数据）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../data/models/download.dart';
import '../../domain/entities/player/player.dart';
import '../../domain/entities/playback/playback.dart';
import '../../domain/entities/spider/spider_models.dart';
import '../../domain/entities/tmdb/tmdb_models.dart';
import '../../domain/usecases/usecases.dart';
import '../../platform/download/download.dart';
import '../pages/player/player_page.dart';
import '../theme/tokens/colors.dart';
import '../theme/tokens/radii.dart';
import '../theme/tokens/spacing.dart';
import '../theme/tokens/typography.dart';
import 'platform_async_image.dart';
import 'vbox/vbox.dart';

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

  /// TMDB 用例（G-06；宿主未装配时为 null → 跳过增强，回退站点数据）。
  TmdbUseCases? _tmdbUc;

  /// TMDB 增强结果（封面 / 演职）。
  TmdbEnrichment? _tmdb;
  Failure? _error;
  bool _loaded = false;
  bool _playing = false;
  int _fromIndex = 0;
  int _episodeIndex = 0;
  bool _expanded = false;
  bool _synopsisExpanded = false;

  @override
  void initState() {
    super.initState();
    // 用例引用在 initState 缓存，避免跨 async gap 使用 context
    _uc = context.read<DetailPlaybackUseCases>();
    _tmdbUc = _readTmdbUseCases();
    _load();
  }

  /// 读取 TMDB 用例（宿主未装配 [TmdbUseCases] Provider 时返回 null）。
  TmdbUseCases? _readTmdbUseCases() {
    try {
      return context.read<TmdbUseCases>();
    } catch (_) {
      return null;
    }
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
    // 详情就绪后异步拉取 TMDB 增强（对齐 iOS `loadTMDBData`，不阻塞首屏）。
    if (_detail != null) unawaited(_loadTmdb());
  }

  /// TMDB 详情增强（对齐 iOS `VideoDetailView.loadTMDBData`）。
  ///
  /// 未启用 / 未配置代理 / 无匹配 / 请求失败 → 保持 null，UI 回退站点数据。
  Future<void> _loadTmdb() async {
    final TmdbUseCases? uc = _tmdbUc;
    final PlaybackDetail? d = _detail;
    if (uc == null || d == null) return;
    final Result<TmdbEnrichment?> result = await uc.enrich(
      name: d.vod.vodName,
      year: d.vod.vodYear,
    );
    if (!mounted) return;
    final TmdbEnrichment? enrichment = result.valueOrNull;
    if (enrichment == null || enrichment.isEmpty) return;
    setState(() => _tmdb = enrichment);
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
    final String from = d.froms[lineIndex.clamp(0, d.froms.length - 1)];
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

      if (!mounted) return;
      // Wave A · R-渲2：解析成功后进入全屏播放页（播放生命周期由播放页持有）。
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => PlayerPage(
            source: PlayerSource(
              url: url,
              title: d.vod.vodName,
              headers: pc?.header ?? const <String, String>{},
            ),
            title: d.vod.vodName,
            subtitle: episode.name,
            episodes: visible,
            initialEpisodeIndex: _episodeIndex.clamp(0, visible.length - 1),
            onResolveEpisode: _resolveEpisodeSource,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast('播放失败：$e');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  /// 选集重开解析器（Wave A · R-渲2）：单集 → 播放源（复用 [DetailPlaybackUseCases]）。
  Future<PlayerSource?> _resolveEpisodeSource(PlaybackEpisode episode) async {
    final PlaybackDetail? d = _detail;
    if (d == null) return null;
    final Result<PlayerContentResult> result =
        await _uc.resolvePlayUrl(detail: d, episode: episode);
    final PlayerContentResult? pc = result.valueOrNull;
    final String? url = _firstUrl(pc);
    if (url == null || url.isEmpty) return null;
    return PlayerSource(
      url: url,
      title: d.vod.vodName,
      headers: pc?.header ?? const <String, String>{},
    );
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

  // ─────────────── 下载选择 ───────────────

  Future<void> _showDownloadSheet() async {
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    if (visible.isEmpty) {
      _toast('暂无剧集，无法下载');
      return;
    }
    final List<int>? picked = await showModalBottomSheet<List<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _DownloadSelectionSheet(
        episodes: visible,
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    await _enqueueDownloads(picked);
  }

  /// 下载接线（G-02）：逐集解析真实地址 → 建 [Download] 记录 → 交
  /// [DownloadManager] 入队（对齐 iOS `VideoDetailView.handleBatchDownload`）。
  ///
  /// 字段映射与 iOS 一致：`sourceType=normal` / `engineKey` / `vodId` /
  /// `jishu=index+1`；`laiyuan` 用站点显示名（iOS `allSources.first?.name`）。
  /// 差异登记：iOS 入队时存选集地址、下载启动时惰性解析；Flutter 此处复用
  /// 播放链路 `resolvePlayUrl` 先解析为真实直链再入队——结果等价，且避免
  /// 全局 DownloadManager 需要共享「当前详情」的跨页状态。解析失败的单集
  /// 跳过并在提示中汇总。
  Future<void> _enqueueDownloads(List<int> picked) async {
    final PlaybackDetail? d = _detail;
    if (d == null) return;
    final DownloadManager manager = context.read<DownloadManager>();
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    int added = 0;
    final List<String> failed = <String>[];
    for (final int index in picked) {
      if (index >= visible.length) continue;
      final PlaybackEpisode episode = visible[index];
      final String label =
          episode.name.isEmpty ? '第${index + 1}集' : episode.name;

      final Result<PlayerContentResult> result =
          await _uc.resolvePlayUrl(detail: d, episode: episode);
      final PlayerContentResult? pc = result.valueOrNull;
      final String? url = _firstUrl(pc);
      if (url == null || url.isEmpty) {
        failed.add(label);
        continue;
      }

      final String headers =
          jsonEncode(pc?.header ?? const <String, String>{});
      await manager.enqueue(
        Download(
          name: '${d.vod.vodName} $label',
          laiyuan: d.site.name,
          imgurl: d.vod.vodPic,
          detailurl: widget.vodId,
          playurl: url,
          jishu: index + 1,
          addedAt: now,
          sourceType: 'normal',
          engineKey: d.vod.engineKey,
          vodId: widget.vodId,
          headers: headers,
        ),
      );
      added++;
    }

    if (!mounted) return;
    if (added > 0 && failed.isEmpty) {
      _toast('已添加 $added 集到下载');
    } else if (added > 0) {
      _toast('已添加 $added 集到下载，${failed.length} 集解析失败已跳过');
    } else {
      _toast('${failed.length} 集解析失败，未添加下载');
    }
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
      padding: VboxSpacing.page,
      children: <Widget>[
        _buildHeader(d),
        const SizedBox(height: VboxSpacing.lg),
        _buildSynopsis(d),
        const SizedBox(height: VboxSpacing.lg),
        _buildCast(d),
        const SizedBox(height: VboxSpacing.lg),
        _buildLineChips(d),
        const SizedBox(height: VboxSpacing.lg),
        _buildEpisodes(d),
        const SizedBox(height: VboxSpacing.xl),
        _buildButtons(),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: VboxRadii.button,
          child: SizedBox(
            width: 120,
            height: 168,
            child: PlatformAsyncImage(
              // G-06：TMDB 有海报则替换站点封面（对齐 iOS `tmdbPosterURL`）。
              url: _tmdb?.posterUrl ?? vod.vodPic,
              fit: BoxFit.cover,
              placeholderColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: VboxSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                vod.vodName,
                style: TextStyle(
                  fontSize: VboxTypography.s18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: VboxSpacing.sm),
              _metaLine(scheme, <String?>[
                if (vod.vodRemarks?.isNotEmpty ?? false) vod.vodRemarks,
              ], Icons.schedule),
              const SizedBox(height: VboxSpacing.xs),
              _metaLine(scheme, <String?>[
                if (vod.vodYear?.isNotEmpty ?? false) vod.vodYear,
                if (vod.vodArea?.isNotEmpty ?? false) vod.vodArea,
              ], Icons.calendar_today_outlined),
              if ((vod.vodActor?.isNotEmpty ?? false) ||
                  (vod.vodDirector?.isNotEmpty ?? false)) ...<Widget>[
                const SizedBox(height: VboxSpacing.xs),
                _metaLine(scheme, <String?>[
                  if (vod.vodDirector?.isNotEmpty ?? false) '导演 ${vod.vodDirector}',
                  if (vod.vodActor?.isNotEmpty ?? false) '主演 ${vod.vodActor}',
                ], Icons.people_outline, maxLines: 3),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaLine(ColorScheme scheme, List<String?> parts, IconData icon,
      {int maxLines = 2}) {
    final String text = parts.whereType<String>().join(' · ');
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: VboxTypography.s12, color: scheme.onSurfaceVariant),
        const SizedBox(width: VboxSpacing.xs),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: VboxTypography.s12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSynopsis(PlaybackDetail d) {
    final String content = d.vod.vodContent?.trim() ?? '';
    if (content.isEmpty) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle('剧情简介', scheme),
        const SizedBox(height: VboxSpacing.sm),
        Text(
          content,
          maxLines: _synopsisExpanded ? null : 3,
          overflow: _synopsisExpanded ? null : TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: VboxTypography.s13,
            height: 1.45,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (content.length > 36)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  setState(() => _synopsisExpanded = !_synopsisExpanded),
              child: Text(_synopsisExpanded ? '收起' : '展开'),
            ),
          ),
      ],
    );
  }

  Widget _buildCast(PlaybackDetail d) {
    // G-06：TMDB 演职人员有数据则整体替换站点（豆瓣）演职（对齐 iOS）。
    final TmdbEnrichment? tmdb = _tmdb;
    final List<String> people = tmdb != null && tmdb.hasCredits
        ? <String>[
            ...tmdb.directors.map((TmdbPerson p) => '导演 ${p.name}'),
            ...tmdb.actors.map((TmdbPerson p) => p.name),
            ...tmdb.writers.map((TmdbPerson p) => '编剧 ${p.name}'),
          ]
        : <String>[
            if (d.vod.vodDirector?.isNotEmpty ?? false)
              ...d.vod.vodDirector!.split(RegExp(r'[,，、/\s]+'))
                  .where((String s) => s.trim().isNotEmpty)
                  .map((String s) => '导演 ${s.trim()}'),
            if (d.vod.vodActor?.isNotEmpty ?? false)
              ...d.vod.vodActor!.split(RegExp(r'[,，、/\s]+'))
                  .where((String s) => s.trim().isNotEmpty)
                  .map((String s) => s.trim()),
          ];
    if (people.isEmpty) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle('演职人员', scheme),
        const SizedBox(height: VboxSpacing.sm),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: VboxSpacing.sm),
            itemBuilder: (BuildContext context, int index) => _CastChip(
              label: people[index],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, ColorScheme scheme) => Text(
        text,
        style: TextStyle(
          fontSize: VboxTypography.s16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      );

  Widget _buildLineChips(PlaybackDetail d) {
    if (d.froms.length <= 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle('播放源', Theme.of(context).colorScheme),
        const SizedBox(height: VboxSpacing.sm),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: d.froms.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: VboxSpacing.sm),
            itemBuilder: (BuildContext context, int index) => VboxChip(
              label: d.froms[index],
              dense: true,
              selected: index == _fromIndex,
              onTap: () {
                if (index == _fromIndex) return;
                setState(() {
                  _fromIndex = index;
                  _episodeIndex = 0;
                  _expanded = false;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodes(PlaybackDetail d) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _sectionTitle(
                visible.isEmpty ? '剧集列表' : '剧集列表 · 共 ${visible.length} 集',
                scheme,
              ),
            ),
            if (visible.length > 8)
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.unfold_less : Icons.unfold_more,
                  size: VboxTypography.s16,
                ),
                label: Text(_expanded ? '收起' : '展开'),
              ),
          ],
        ),
        const SizedBox(height: VboxSpacing.sm),
        if (visible.isEmpty)
          Text(
            '暂无剧集',
            style: TextStyle(
              fontSize: VboxTypography.s13,
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          _EpisodeGrid(
            episodes: visible,
            selectedIndex: _episodeIndex,
            expanded: _expanded,
            onSelect: (int index) => setState(() => _episodeIndex = index),
          ),
      ],
    );
  }

  Widget _buildButtons() {
    final PlaybackDetail? d = _detail;
    final bool enabled = d != null && _episodesForLine(_fromIndex).isNotEmpty;
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: _playing || !enabled ? null : _play,
            icon: _playing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_playing ? '播放中…' : '立即播放'),
          ),
        ),
        const SizedBox(width: VboxSpacing.md),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: !enabled ? null : _showDownloadSheet,
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载'),
          ),
        ),
      ],
    );
  }
}

/// 剧集宫格（自适应列数 + 折叠/展开）。
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.episodes,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelect,
  });

  final List<PlaybackEpisode> episodes;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<PlaybackEpisode> shown =
        expanded ? episodes : episodes.take(8).toList(growable: false);
    final double height = expanded
        ? ((shown.length / 4).ceil() * 44.0).clamp(176.0, 400.0)
        : ((shown.length / 4).ceil() * 44.0).clamp(88.0, 176.0);

    return SizedBox(
      height: height,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: VboxSpacing.sm,
          crossAxisSpacing: VboxSpacing.sm,
          childAspectRatio: 1.8,
        ),
        itemCount: shown.length,
        itemBuilder: (BuildContext context, int index) {
          final PlaybackEpisode ep = shown[index];
          final bool selected = index == selectedIndex;
          return _EpisodeCell(
            label: ep.name.isEmpty ? '第${index + 1}集' : ep.name,
            selected: selected,
            color: scheme,
            onTap: () => onSelect(index),
          );
        },
      ),
    );
  }
}

/// 单集宫格项（选中态带播放角标）。
class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ColorScheme color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? VboxColors.selected : color.onSurface;
    final Color background =
        selected ? VboxColors.selected.withValues(alpha: 0.20) : color.surfaceContainerHighest;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: VboxRadii.button,
        side: selected
            ? const BorderSide(color: VboxColors.selected)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: VboxSpacing.symmetric(horizontal: VboxSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (selected) ...<Widget>[
                const Icon(Icons.play_arrow, size: VboxTypography.s14),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: VboxTypography.s12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 演职人员 chip。
class _CastChip extends StatelessWidget {
  const _CastChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: VboxSpacing.symmetric(horizontal: VboxSpacing.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: VboxRadii.badge,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: VboxTypography.s12,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 下载选集 sheet（多选 + 全选 + 确认）。
class _DownloadSelectionSheet extends StatefulWidget {
  const _DownloadSelectionSheet({required this.episodes});

  final List<PlaybackEpisode> episodes;

  @override
  State<_DownloadSelectionSheet> createState() =>
      _DownloadSelectionSheetState();
}

class _DownloadSelectionSheetState extends State<_DownloadSelectionSheet> {
  final Set<int> _selected = <int>{};

  void _toggleAll() {
    setState(() {
      if (_selected.length == widget.episodes.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(List<int>.generate(widget.episodes.length, (int i) => i));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(VboxSpacing.lg, 0, VboxSpacing.lg, VboxSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '下载选集 · 共 ${widget.episodes.length} 集',
                    style: TextStyle(
                      fontSize: VboxTypography.s16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                TextButton(onPressed: _toggleAll, child: const Text('全选')),
              ],
            ),
            const SizedBox(height: VboxSpacing.sm),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: VboxSpacing.sm,
                  crossAxisSpacing: VboxSpacing.sm,
                  childAspectRatio: 1.8,
                ),
                itemCount: widget.episodes.length,
                itemBuilder: (BuildContext context, int index) {
                  final bool checked = _selected.contains(index);
                  final PlaybackEpisode ep = widget.episodes[index];
                  final String label = ep.name.isEmpty ? '第${index + 1}集' : ep.name;
                  return Material(
                    color: checked
                        ? Colors.blue.withValues(alpha: 0.15)
                        : scheme.surfaceContainerHighest,
                    shape: const RoundedRectangleBorder(
                      borderRadius: VboxRadii.button,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() {
                        if (checked) {
                          _selected.remove(index);
                        } else {
                          _selected.add(index);
                        }
                      }),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            checked
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: VboxTypography.s13,
                            color: checked ? Colors.blue : scheme.outline,
                          ),
                          const SizedBox(width: VboxSpacing.xs),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: VboxTypography.s12,
                                color: checked ? Colors.blue : scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: VboxSpacing.md),
            FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected.toList()..sort()),
              child: Text('下载选中 (${_selected.length})'),
            ),
          ],
        ),
      ),
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