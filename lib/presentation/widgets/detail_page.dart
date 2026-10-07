/// 详情页：全屏封面背景 + 可滚动内容层（对齐 iOS `VideoDetailView`）。
///
/// 对齐 iOS `VideoDetailView`（`vbox/Views/PlayerViews.swift#L35` / 背景层 L1150 /
/// 内容层 L1192）：
/// - **双层结构**：底层全屏铺满封面（TMDB poster/backdrop 优先，回退豆瓣站点封面）
///   并叠加自 45% 高度起的黑色渐暗遮罩；上层为安全区内可滚动内容；
/// - 内容序：片名/logo + 剧情标签行 → 「立即播放」胶囊按钮 → 演职人员（分类 tab +
///   60×90 小方头像卡横滑）→ 剧情简介（含收藏心形）→ 线路 chips → 剧集宫格；
/// - 剧集宫格对齐 iOS `episodeSection`：标题 + 排序（倒序）+ 集数 + 宫格展开弹窗
///   （`EpisodeExpandPopup`：下载多选模式 / 全选 / 确认批量下载）。
///
/// 数据通路：[DetailPlaybackUseCases].loadDetail / resolvePlayUrl；
/// 封面 / 演职增强：[TmdbUseCases].enrich（G-06，未启用或未命中时回退站点数据）；
/// 收藏 / 历史：[FavoriteUseCases] / [HistoryUseCases]（全局 Provider 注入）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/download.dart';
import '../../domain/entities/cloud/cloud_drive.dart';
import '../../domain/entities/library/library.dart';
import '../../domain/entities/player/player.dart';
import '../../domain/entities/playback/playback.dart';
import '../../domain/entities/spider/spider_models.dart';
import '../../domain/entities/tmdb/tmdb_models.dart';
import '../../domain/usecases/usecases.dart';
import '../../platform/download/download.dart';
import '../../platform/player/pan_player.dart';
import '../pages/cloud/files.dart';
import '../pages/player/player_page.dart';
import '../theme/tokens/colors.dart';
import '../theme/tokens/radii.dart';
import 'platform_async_image.dart';

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

  /// 收藏 / 历史用例（宿主未装配时为 null → 静默跳过）。
  FavoriteUseCases? _favUc;
  HistoryUseCases? _histUc;

  /// TMDB 增强结果（封面 / 演职）。
  TmdbEnrichment? _tmdb;
  Failure? _error;
  bool _loaded = false;
  bool _playing = false;
  bool _favorite = false;
  int _fromIndex = 0;
  int _episodeIndex = 0;
  bool _episodesReversed = false;
  String _castTab = '全部';

  /// 观看记录写入节流时间戳（毫秒；对齐 iOS 5s 节流）。
  int _lastHistoryWriteMs = 0;

  @override
  void initState() {
    super.initState();
    // 用例引用在 initState 缓存，避免跨 async gap 使用 context
    _uc = context.read<DetailPlaybackUseCases>();
    _tmdbUc = _tryRead<TmdbUseCases>();
    _favUc = _tryRead<FavoriteUseCases>();
    _histUc = _tryRead<HistoryUseCases>();
    _load();
  }

  /// 读取可选 Provider（宿主未装配时返回 null）。
  T? _tryRead<T>() {
    try {
      return context.read<T>();
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
    if (_detail != null) {
      // 详情就绪后异步拉取 TMDB 增强（对齐 iOS `loadTMDBData`，不阻塞首屏）。
      unawaited(_loadTmdb());
      unawaited(_checkFavorite());
    }
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

  PlaybackEpisode? get _currentEpisode {
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    if (visible.isEmpty) return null;
    return visible[_episodeIndex.clamp(0, visible.length - 1)];
  }

  // ─────────────── 收藏 / 历史 ───────────────

  /// 读取收藏态（对齐 iOS `checkFavorite`）。
  Future<void> _checkFavorite() async {
    final FavoriteUseCases? uc = _favUc;
    if (uc == null) return;
    final Result<bool> result = await uc.isFavorite(widget.vodId);
    if (!mounted) return;
    setState(() => _favorite = result.valueOrNull ?? false);
  }

  /// 切换收藏（对齐 iOS `toggleFavorite`）。
  Future<void> _toggleFavorite() async {
    final FavoriteUseCases? uc = _favUc;
    final PlaybackDetail? d = _detail;
    if (uc == null || d == null) return;
    final Result<bool> result = await uc.toggle(
      FavoriteItem(
        name: d.vod.vodName,
        laiyuan: widget.siteKey,
        imgurl: d.vod.vodPic,
        detailurl: widget.vodId,
        xianlu: _fromIndex,
        jishu: _episodeIndex,
        addedAt: TimeUtils.nowUnixSeconds(),
      ),
    );
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      _toast('收藏操作失败：$failure');
      return;
    }
    final bool now = result.valueOrNull ?? false;
    setState(() => _favorite = now);
    _toast(now ? '已加入收藏' : '已取消收藏');
  }

  /// 写入观看记录（对齐 iOS 播放开始 / 进度 >5s 落库）。
  Future<void> _recordHistory({double progress = 0}) async {
    final HistoryUseCases? uc = _histUc;
    final PlaybackDetail? d = _detail;
    if (uc == null || d == null) return;
    await uc.record(
      HistoryItem(
        name: d.vod.vodName,
        laiyuan: widget.siteKey,
        imgurl: d.vod.vodPic,
        detailurl: widget.vodId,
        xianlu: _fromIndex,
        jishu: _episodeIndex,
        progress: progress,
        lastPlayedAt: TimeUtils.nowUnixSeconds(),
      ),
    );
  }

  /// 播放进度回调（对齐 iOS：进度 >5s 且距上次落库 >5s 才写入）。
  void _onPlaybackProgress(PlaybackProgress p) {
    if (p.durationMs <= 0 || p.positionMs < 5000) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastHistoryWriteMs < 5000) return;
    _lastHistoryWriteMs = now;
    final double progress = (p.positionMs / p.durationMs).clamp(0.0, 1.0);
    unawaited(_recordHistory(progress: progress));
  }

  // ─────────────── 播放 ───────────────

  Future<void> _playEpisode(PlaybackEpisode episode) async {
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    final int index = visible.indexWhere(
      (PlaybackEpisode e) => e.url == episode.url && e.name == episode.name,
    );
    if (index >= 0) setState(() => _episodeIndex = index);
    await _play();
  }

  Future<void> _play() async {
    final PlaybackDetail? d = _detail;
    if (d == null || _playing) return;
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    if (visible.isEmpty) return;
    final PlaybackEpisode episode =
        visible[_episodeIndex.clamp(0, visible.length - 1)];

    // F-P07：网盘分享链接 → 走网盘文件列表（分享模式）选集播放。
    final CloudDriveType? drive = CloudDriveType.fromShareUrl(episode.url);
    if (drive != null) {
      await _openCloudFiles(drive, episode.url);
      return;
    }

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

      // 播放开始即写入观看记录（对齐 iOS 播放启动落库）。
      unawaited(_recordHistory());

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
            onProgress: _onPlaybackProgress,
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

  /// 打开网盘文件列表（分享模式）选集播放（对齐 iOS 播放器 `handleDriveUrl`）。
  Future<void> _openCloudFiles(CloudDriveType type, String shareUrl) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CloudDriveFilesPage(
          driveType: type,
          shareUrl: shareUrl,
          panPlayer: PanPlayer(),
        ),
      ),
    );
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

  // ─────────────── 下载 ───────────────

  /// 下载接线（G-02）：逐集解析真实地址 → 建 [Download] 记录 → 交
  /// [DownloadManager] 入队（对齐 iOS `VideoDetailView.handleBatchDownload`）。
  Future<void> _enqueueDownloads(List<PlaybackEpisode> episodes) async {
    final PlaybackDetail? d = _detail;
    if (d == null || episodes.isEmpty) return;
    final DownloadManager manager = context.read<DownloadManager>();
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);

    int added = 0;
    final List<String> failed = <String>[];
    for (int i = 0; i < episodes.length; i++) {
      final PlaybackEpisode episode = episodes[i];
      final int original =
          visible.indexWhere((PlaybackEpisode e) => e.url == episode.url && e.name == episode.name);
      final int jishu = original >= 0 ? original + 1 : i + 1;
      final String label =
          episode.name.isEmpty ? '第$jishu集' : episode.name;

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
          jishu: jishu,
          addedAt: TimeUtils.nowUnixSeconds(),
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

  // ─────────────── 剧集弹窗 ───────────────

  /// 打开剧集展开弹窗（对齐 iOS `EpisodeExpandPopup`）。
  Future<void> _showEpisodePopup({bool downloadMode = false}) async {
    final List<PlaybackEpisode> visible = _episodesForLine(_fromIndex);
    if (visible.isEmpty) {
      _toast('暂无剧集');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (BuildContext ctx) => _EpisodeExpandDialog(
        title: '剧集列表',
        episodes: visible,
        initialReversed: _episodesReversed,
        initialDownloadMode: downloadMode,
        onReversedChanged: (bool value) =>
            setState(() => _episodesReversed = value),
        onPlay: (PlaybackEpisode episode) {
          Navigator.of(ctx).pop();
          unawaited(_playEpisode(episode));
        },
        onDownload: (List<PlaybackEpisode> episodes) {
          Navigator.of(ctx).pop();
          unawaited(_enqueueDownloads(episodes));
        },
      ),
    );
  }

  // ─────────────── UI ───────────────

  @override
  Widget build(BuildContext context) {
    final String title = widget.title ?? _detail?.vod.vodName ?? '详情';
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
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
      return const Center(
        child: Text('详情为空', style: TextStyle(color: Colors.white70)),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.maxHeight;
        return Stack(
          children: <Widget>[
            Positioned.fill(child: _buildBackground(d, height)),
            Positioned.fill(child: _buildContent(d, height)),
          ],
        );
      },
    );
  }

  void _retry() {
    setState(() {
      _loaded = false;
      _error = null;
      _detail = null;
      _tmdb = null;
    });
    _load();
  }

  /// 背景层（对齐 iOS `backgroundLayer` + `bottomDimmingOverlay`）。
  Widget _buildBackground(PlaybackDetail d, double height) {
    final String? cover = _tmdb?.posterUrl ?? _tmdb?.backdropUrl ?? d.vod.vodPic;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: Colors.black),
        if (cover != null && cover.trim().isNotEmpty)
          PlatformAsyncImage(
            url: cover,
            fit: BoxFit.cover,
            placeholderColor: Colors.black,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: height * 0.55,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x1A000000),
                  Color(0x59000000),
                ],
                stops: <double>[0.0, 0.35, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 内容滚动层（对齐 iOS `contentLayer`：顶部 30% 透明露出封面）。
  Widget _buildContent(PlaybackDetail d, double height) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: height * 0.30),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 20,
              children: <Widget>[
                _buildTitleBlock(d),
                _buildPlayButton(),
                _buildCast(d),
                _buildSynopsis(d),
                _buildEpisodeSection(d),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 片名 / logo / 剧情标签行（对齐 iOS HeroTitleView 段）。
  Widget _buildTitleBlock(PlaybackDetail d) {
    final VodItem vod = d.vod;
    final String? logo = _tmdb?.logoUrl;
    final bool hasLogo = logo != null && logo.isNotEmpty;
    final List<String> meta = <String>[
      if (vod.vodYear?.isNotEmpty ?? false) vod.vodYear!,
      if (vod.vodArea?.isNotEmpty ?? false) vod.vodArea!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasLogo)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 70),
            child: PlatformAsyncImage(
              url: logo,
              fit: BoxFit.contain,
              placeholderColor: Colors.transparent,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        if (hasLogo) const SizedBox(height: 12),
        Text(
          vod.vodName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: hasLogo ? 14 : 26,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: hasLogo ? 0.9 : 1.0),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: const Text(
                '剧情',
                style: TextStyle(fontSize: 11, color: Color(0xE6FFFFFF)),
              ),
            ),
            if (meta.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  meta.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
            if (vod.vodRemarks?.isNotEmpty ?? false) ...<Widget>[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  vod.vodRemarks!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 立即播放胶囊按钮（对齐 iOS `playButton`）。
  Widget _buildPlayButton() {
    final bool enabled =
        _detail != null && _episodesForLine(_fromIndex).isNotEmpty && !_playing;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: VboxColors.detailPlayButton,
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              onTap: enabled ? _play : null,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (_playing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    else
                      const Icon(Icons.play_arrow, size: 16, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      _playing ? '播放中…' : '立即播放',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 演职人员（分类 tab + 小方头像卡横滑，对齐 iOS `castSection`）。
  Widget _buildCast(PlaybackDetail d) {
    final (List<_CastMember> actors, List<_CastMember> directors,
        List<_CastMember> writers) = _castData(d);
    final bool hasAny =
        actors.isNotEmpty || directors.isNotEmpty || writers.isNotEmpty;
    if (!hasAny) return const SizedBox.shrink();
    final List<_CastMember> people = switch (_castTab) {
      '演员' => actors,
      '导演' => directors,
      '编剧' => writers,
      _ => <_CastMember>[...actors, ...directors, ...writers],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          spacing: 12,
          children: <Widget>[
            for (final String tab in <String>['全部', '演员', '导演', '编剧'])
              if (_castAvailable(tab, actors, directors, writers))
                _castTabButton(tab),
          ],
        ),
        const SizedBox(height: 12),
        if (people.isEmpty)
          Text(
            '暂无$_castTab信息',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          )
        else
          SizedBox(
            height: 136,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: 14),
              itemBuilder: (BuildContext context, int index) =>
                  _CastPersonCard(person: people[index]),
            ),
          ),
      ],
    );
  }

  bool _castAvailable(
    String tab,
    List<_CastMember> actors,
    List<_CastMember> directors,
    List<_CastMember> writers,
  ) =>
      switch (tab) {
        '全部' => actors.isNotEmpty || directors.isNotEmpty || writers.isNotEmpty,
        '演员' => actors.isNotEmpty,
        '导演' => directors.isNotEmpty,
        '编剧' => writers.isNotEmpty,
        _ => false,
      };

  Widget _castTabButton(String tab) {
    final bool selected = _castTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _castTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.2) : null,
          borderRadius: BorderRadius.circular(VboxRadii.r6),
        ),
        child: Text(
          tab,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  /// 演职人员数据（TMDB 有则整体替换站点文本，对齐 iOS）。
  (
    List<_CastMember>,
    List<_CastMember>,
    List<_CastMember>,
  ) _castData(PlaybackDetail d) {
    final TmdbEnrichment? tmdb = _tmdb;
    if (tmdb != null && tmdb.hasCredits) {
      return (
        tmdb.actors
            .map((TmdbPerson p) => _CastMember(
                  name: p.name,
                  coverUrl: p.coverUrl,
                  role: p.character,
                ))
            .toList(growable: false),
        tmdb.directors
            .map((TmdbPerson p) => _CastMember(
                  name: p.name,
                  coverUrl: p.coverUrl,
                  role: p.character ?? '导演',
                ))
            .toList(growable: false),
        tmdb.writers
            .map((TmdbPerson p) => _CastMember(
                  name: p.name,
                  coverUrl: p.coverUrl,
                  role: p.character ?? '编剧',
                ))
            .toList(growable: false),
      );
    }
    return (
      _splitNames(d.vod.vodActor)
          .map((String s) => _CastMember(name: s))
          .toList(growable: false),
      _splitNames(d.vod.vodDirector)
          .map((String s) => _CastMember(name: s, role: '导演'))
          .toList(growable: false),
      const <_CastMember>[],
    );
  }

  List<String> _splitNames(String? raw) => (raw ?? '')
      .split(RegExp(r'[,，、/\s]+'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);

  /// 剧情简介 + 收藏心形（对齐 iOS `synopsisSection`）。
  Widget _buildSynopsis(PlaybackDetail d) {
    final String content = d.vod.vodContent?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '剧情简介',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _toggleFavorite,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                _favorite ? Icons.favorite : Icons.favorite_border,
                size: 24,
                color: _favorite
                    ? VboxColors.detailSelected
                    : Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          content.isEmpty ? '暂无简介' : content,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  /// 剧集列表（对齐 iOS `episodeSection`）。
  Widget _buildEpisodeSection(PlaybackDetail d) {
    final List<PlaybackEpisode> episodes = _episodesForLine(_fromIndex);
    final List<PlaybackEpisode> ordered = _episodesReversed
        ? episodes.reversed.toList(growable: false)
        : episodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '剧集列表',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            if (episodes.isNotEmpty)
              IconButton(
                onPressed: () =>
                    setState(() => _episodesReversed = !_episodesReversed),
                icon: Icon(
                  Icons.swap_vert,
                  size: 18,
                  color: _episodesReversed
                      ? VboxColors.detailSelected
                      : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            Text(
              episodes.isEmpty ? '暂无集数' : '共 ${episodes.length} 集',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            if (episodes.isNotEmpty)
              IconButton(
                onPressed: () => _showEpisodePopup(),
                icon: Icon(
                  Icons.grid_view,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            if (episodes.isNotEmpty)
              IconButton(
                onPressed: () => _showEpisodePopup(downloadMode: true),
                icon: Icon(
                  Icons.download_outlined,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        if (d.froms.length > 1) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: d.froms.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int index) =>
                  _lineChip(d.froms[index], index == _fromIndex, () {
                if (index == _fromIndex) return;
                setState(() {
                  _fromIndex = index;
                  _episodeIndex = 0;
                });
              }),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (episodes.isEmpty)
          Text(
            '暂无剧集',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 76,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
            ),
            itemCount: ordered.length,
            itemBuilder: (BuildContext context, int index) {
              final PlaybackEpisode ep = ordered[index];
              final int visibleIndex = episodes.indexWhere(
                (PlaybackEpisode e) => e.url == ep.url && e.name == ep.name,
              );
              final bool selected = visibleIndex == _episodeIndex;
              return _EpisodeCell(
                label: ep.name.isEmpty ? '第${index + 1}集' : ep.name,
                selected: selected,
                onTap: () => setState(() {
                  if (visibleIndex >= 0) _episodeIndex = visibleIndex;
                }),
              );
            },
          ),
      ],
    );
  }

  Widget _lineChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? VboxColors.detailSelected
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(VboxRadii.r8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: Colors.white.withValues(alpha: selected ? 1.0 : 0.8),
          ),
        ),
      ),
    );
  }
}

/// 演职人员卡片（对齐 iOS `CastPersonCard`：60×90 头像 + 姓名 + 角色）。
class _CastPersonCard extends StatelessWidget {
  const _CastPersonCard({required this.person});

  final _CastMember person;

  @override
  Widget build(BuildContext context) {
    final String? role = person.role;
    return Column(
      spacing: 6,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(VboxRadii.r8),
          child: SizedBox(
            width: 60,
            height: 90,
            child: PlatformAsyncImage(
              url: person.coverUrl,
              fit: BoxFit.cover,
              placeholderColor: Colors.grey.withValues(alpha: 0.3),
              placeholder:
                  ColoredBox(color: Colors.grey.withValues(alpha: 0.3)),
              errorBuilder: (_, __, ___) =>
                  ColoredBox(color: Colors.grey.withValues(alpha: 0.3)),
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
        if (role != null && role.isNotEmpty)
          SizedBox(
            width: 60,
            child: Text(
              role,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }
}

/// 演职人员项（名称 + 可选头像 / 角色）。
class _CastMember {
  const _CastMember({required this.name, this.coverUrl, this.role});

  final String name;
  final String? coverUrl;
  final String? role;
}

/// 单集宫格项（对齐 iOS 剧集网格：白色 12% 底 + 白字）。
class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VboxRadii.r8),
        side: selected
            ? const BorderSide(color: VboxColors.detailSelected, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 剧集展开弹窗（对齐 iOS `EpisodeExpandPopup`：排序 + 下载多选）。
class _EpisodeExpandDialog extends StatefulWidget {
  const _EpisodeExpandDialog({
    required this.title,
    required this.episodes,
    required this.initialReversed,
    required this.initialDownloadMode,
    required this.onReversedChanged,
    required this.onPlay,
    required this.onDownload,
  });

  final String title;
  final List<PlaybackEpisode> episodes;
  final bool initialReversed;
  final bool initialDownloadMode;
  final ValueChanged<bool> onReversedChanged;
  final ValueChanged<PlaybackEpisode> onPlay;
  final ValueChanged<List<PlaybackEpisode>> onDownload;

  @override
  State<_EpisodeExpandDialog> createState() => _EpisodeExpandDialogState();
}

class _EpisodeExpandDialogState extends State<_EpisodeExpandDialog> {
  late bool _reversed = widget.initialReversed;
  late bool _downloadMode = widget.initialDownloadMode;
  final Set<int> _selected = <int>{};

  List<PlaybackEpisode> get _ordered => _reversed
      ? widget.episodes.reversed.toList(growable: false)
      : widget.episodes;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<PlaybackEpisode> ordered = _ordered;
    // 长名占比高 → 双列（对齐 iOS `useTwoColumns`）。
    final int longCount =
        ordered.where((PlaybackEpisode e) => e.name.length > 8).length;
    final bool twoColumns =
        ordered.isNotEmpty && longCount / ordered.length > 0.3;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VboxRadii.r16),
      ),
      child: SizedBox(
        width: (screen.width - 32).clamp(0, 380).toDouble(),
        height: (screen.height * 0.58).clamp(360.0, screen.height * 0.72),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                spacing: 10,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _downloadMode
                              ? '已选 ${_selected.length} 集'
                              : '共 ${ordered.length} 集',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _reversed = !_reversed;
                      _selected.clear();
                      widget.onReversedChanged(_reversed);
                    }),
                    icon: Icon(
                      Icons.swap_vert,
                      size: 18,
                      color: _reversed
                          ? VboxColors.detailSelected
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      if (_downloadMode && _selected.isNotEmpty) {
                        final List<PlaybackEpisode> picked = _selected
                            .map((int i) => ordered[i])
                            .toList()
                          ..sort((PlaybackEpisode a, PlaybackEpisode b) =>
                              ordered.indexOf(a).compareTo(ordered.indexOf(b)));
                        widget.onDownload(picked);
                      } else {
                        _downloadMode = !_downloadMode;
                        if (!_downloadMode) _selected.clear();
                      }
                    }),
                    icon: Icon(
                      _downloadMode
                          ? (_selected.isEmpty
                              ? Icons.check_circle_outline
                              : Icons.check_circle)
                          : Icons.download_outlined,
                      size: 18,
                      color: _downloadMode && _selected.isNotEmpty
                          ? VboxColors.selected
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: twoColumns ? 2 : 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: twoColumns ? 3.0 : 2.0,
                  ),
                  itemCount: ordered.length,
                  itemBuilder: (BuildContext context, int index) {
                    final PlaybackEpisode ep = ordered[index];
                    final bool checked = _selected.contains(index);
                    final String label =
                        ep.name.isEmpty ? '第${index + 1}集' : ep.name;
                    return Material(
                      color: _downloadMode && checked
                          ? VboxColors.selected.withValues(alpha: 0.15)
                          : scheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(VboxRadii.r8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          if (_downloadMode) {
                            setState(() {
                              if (checked) {
                                _selected.remove(index);
                              } else {
                                _selected.add(index);
                              }
                            });
                          } else {
                            widget.onPlay(ep);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: twoColumns ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _downloadMode && checked
                                        ? VboxColors.selected
                                        : scheme.onSurface,
                                  ),
                                ),
                              ),
                              if (_downloadMode) ...<Widget>[
                                const SizedBox(width: 4),
                                Icon(
                                  checked
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 12,
                                  color: checked
                                      ? VboxColors.selected
                                      : scheme.outline,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
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
            const Icon(Icons.error_outline, size: 40, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
