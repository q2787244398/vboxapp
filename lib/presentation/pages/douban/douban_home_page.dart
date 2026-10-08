/// 豆瓣首页（批次 D · D-03）。
///
/// 轮播横幅（TOP250 前若干）+ 区块横向列表（热门电影 / 剧集 / 综艺 / 动漫）。
/// 数据通路：[DoubanUseCases.homeFeed]（用例层并发拉取）。仅浏览，点击不跳转。
///
/// 结构：`DoubanHomePage`（独立页 = AppBar「豆瓣」+ [DoubanHomeView]）与
/// `VboxHomePage`（首页默认内容）**共用**同一 [DoubanHomeView]。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/douban/douban_models.dart';
import '../../../domain/usecases/douban_usecases.dart';
import '../../shell/splash_gate_monitor.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/platform_async_image.dart';
import '../search/search_page.dart';
import 'douban_widgets.dart';

/// 豆瓣独立页（AppBar「豆瓣」+ [DoubanHomeView]）。
class DoubanHomePage extends StatelessWidget {
  /// 构造。
  const DoubanHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('豆瓣')),
      // 对齐 iOS `DoubanHomeView`：条目点击 `triggerSearch(title)` 进入搜索页。
      body: DoubanHomeView(
        onSubjectTap: (DoubanSubject subject) {
          final String kw = subject.title.trim();
          if (kw.isEmpty) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  SearchPage(initialKeyword: kw),
            ),
          );
        },
      ),
    );
  }
}

/// 豆瓣首页内容视图（**不含** Scaffold / AppBar，供首页默认内容与独立页复用）。
class DoubanHomeView extends StatefulWidget {
  /// 构造。
  const DoubanHomeView({super.key, this.onSubjectTap});

  /// 条目点击回调（对齐 iOS `settings.triggerSearch(subject.title)`；
  /// 空则仅浏览）。
  final void Function(DoubanSubject subject)? onSubjectTap;

  @override
  State<DoubanHomeView> createState() => _DoubanHomeViewState();
}

class _DoubanHomeViewState extends State<DoubanHomeView> {
  /// 首页豆瓣数据进程级缓存（对齐 iOS `MainViews.swift` 的静态 `cachedBannerItems`
  /// / `cachedHotMovies` 等 + `hasHomeCache`）：
  /// tab 切换会重建本视图，命中缓存时直接复用、不再发起网络请求。
  static DoubanHomeFeed? _cachedFeed;

  late final DoubanUseCases _uc;

  DoubanHomeFeed? _feed;
  Failure? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _uc = context.read<DoubanUseCases>();
    // 对齐 iOS `init()`：`isLoading = !hasHomeCache`，有缓存先展示缓存。
    _feed = _cachedFeed;
    _loading = _cachedFeed == null;
    // 对齐 iOS `onAppear`：`guard !hasHomeCache else { restore; return }`。
    if (_cachedFeed == null) {
      _load();
    } else {
      _markReadyIfNeeded(_cachedFeed!);
    }
  }

  /// L-壳1 数据门控：首页默认内容（豆瓣）已有可展示数据 → 允许启动页淡出。
  void _markReadyIfNeeded(DoubanHomeFeed feed) {
    if (!feed.isEmpty) {
      SplashGateMonitor.instance.markHomeReady();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final Result<DoubanHomeFeed> result = await _uc.homeFeed();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = result.failureOrNull;
      _feed = result.valueOrNull;
    });
    // 写入进程级缓存（对齐 iOS `loadData` 成功后回填 `cached*`）。
    final DoubanHomeFeed? feed = result.valueOrNull;
    if (feed != null && !feed.isEmpty) {
      _cachedFeed = feed;
      _markReadyIfNeeded(feed);
    }
  }

  /// 栏目 → 图标（SF Symbol → Material 近似，对齐 iOS 各栏目 icon）。
  static IconData _sectionIcon(String title) => switch (title) {
        '影院热映' => Icons.movie,
        '即将上映' => Icons.event,
        '热门电影' => Icons.local_fire_department,
        '一周口碑榜' => Icons.star,
        '新片榜' => Icons.auto_awesome,
        'TOP250' => Icons.workspace_premium,
        '热门剧集' => Icons.tv,
        '华语口碑剧集' => Icons.flag,
        '值得看的英美剧' => Icons.public,
        '热门动漫' => Icons.brush,
        '热门综艺' => Icons.theater_comedy,
        _ => Icons.grid_view,
      };

  @override
  Widget build(BuildContext context) {
    // UI-B2：下拉刷新豆瓣首页。
    return RefreshIndicator(
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Failure? error = _error;
    if (error != null) {
      return DoubanErrorRetry(message: '$error', onRetry: _load);
    }
    final DoubanHomeFeed? feed = _feed;
    if (feed == null || feed.isEmpty) {
      return const DoubanEmptyHint(text: '豆瓣暂无内容\n请稍后重试');
    }
    return ListView(
      // UI-B2：允许内容不足一屏时也能下拉（配合外层 RefreshIndicator）。
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.md),
      children: <Widget>[
        if (feed.banner.isNotEmpty) _buildBanner(feed.banner),
        for (final DoubanHomeSection section in feed.sections) _buildSection(section),
      ],
    );
  }

  Widget _buildBanner(List<DoubanSubject> items) {
    return _DoubanBanner(items: items, onTap: widget.onSubjectTap);
  }

  Widget _buildSection(DoubanHomeSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DoubanSectionHeader(title: section.title, icon: _sectionIcon(section.title)),
        DoubanSubjectRow(
          items: section.items,
          onTap: widget.onSubjectTap,
        ),
      ],
    );
  }
}

/// 轮播横幅（海报 + 底部标题遮罩 + 页码指示；自动轮播，对齐 iOS `BannerCarousel`）。
class _DoubanBanner extends StatefulWidget {
  const _DoubanBanner({required this.items, this.onTap});

  final List<DoubanSubject> items;
  final void Function(DoubanSubject subject)? onTap;

  @override
  State<_DoubanBanner> createState() => _DoubanBannerState();
}

class _DoubanBannerState extends State<_DoubanBanner> {
  /// 自动轮播间隔（对齐 iOS `startAutoPlay` 4s）。
  static const Duration _autoPlayInterval = Duration(seconds: 4);

  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(_autoPlayInterval, (_) => _advance());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _advance() {
    if (!mounted || !_controller.hasClients) return;
    final int next = (_page + 1) % widget.items.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (int i) => setState(() => _page = i),
            itemBuilder: (BuildContext context, int i) {
              final DoubanSubject subject = widget.items[i];
              return Padding(
                padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
                child: GestureDetector(
                  onTap: () => widget.onTap?.call(subject),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        PlatformAsyncImage(url: subject.coverUrl, fit: BoxFit.cover),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(VboxSpacing.md),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.72),
                                ],
                              ),
                            ),
                            child: Text(
                              subject.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: VboxTypography.s16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: VboxSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < widget.items.length; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? scheme.primary : scheme.outlineVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}