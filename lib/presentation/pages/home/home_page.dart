/// 首页内容浏览（批次 D · D-01；批次 A · A9「默认内容改豆瓣」）。
///
/// 唯一真相源：iOS `MainViews.swift` L229-L276「首页视图（豆瓣推荐）」。
///
/// A9 口径（R-11）：
///   · 首页**默认内容 = 豆瓣**（[DoubanHomeView]，对齐 iOS「豆瓣推荐」）；
///   · 源（Spider / CMS）通过顶部「切换源」浮层进入并覆盖展示，**不是**首页默认内容；
///   · **无可用源时不报错**，保持豆瓣默认内容（原 `UnknownFailure('无可用站点')` 已废弃）。
///
/// 站点内容通路：`ContentBrowseUseCases.listSites` + `homeContent`（模式分流在用例层完成），
/// 点击海报 push 详情页。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/douban/douban_models.dart';
import '../../../domain/entities/spider/spider.dart';
import '../../../domain/usecases/usecases.dart';
import '../../shell/splash_gate_monitor.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/detail_page.dart';
import '../../widgets/library_views.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import '../category/category_page.dart';
import '../douban/douban_home_page.dart';
import '../douban/douban_ranking_page.dart';
import '../search/search_page.dart';
import 'source_sheet.dart';

/// 首页（内容浏览）。默认展示豆瓣推荐；切换源后展示对应站点内容。
class VboxHomePage extends StatefulWidget {
  /// 构造。
  const VboxHomePage({super.key});

  @override
  State<VboxHomePage> createState() => _VboxHomePageState();
}

class _VboxHomePageState extends State<VboxHomePage> {
  /// 站点清单进程级缓存（对齐 iOS `MainViews.swift` 的静态缓存口径）：
  /// tab 切换重建本页时直接复用，不再重复请求站点列表。
  static List<SiteConfig>? _cachedSites;

  /// 站点内容按 `siteKey` 的进程级缓存：切回首页 / 复选同一源直接命中，不重复拉取。
  static final Map<String, HomeContentResult> _cachedHomeBySite =
      <String, HomeContentResult>{};

  late final ContentBrowseUseCases _uc;

  List<SiteConfig> _sites = const <SiteConfig>[];
  String? _siteKey;
  HomeContentResult? _home;
  Failure? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _uc = context.read<ContentBrowseUseCases>();
    // 对齐 iOS `HomeView.onAppear`：有缓存先恢复，无缓存才加载。
    final List<SiteConfig>? cachedSites = _cachedSites;
    if (cachedSites != null) {
      _sites = cachedSites;
    } else {
      _loadSites();
    }
  }

  /// 加载站点清单（仅供「切换源」使用；失败 / 为空**不报错**，保持豆瓣默认内容）。
  Future<void> _loadSites() async {
    final Result<List<SiteConfig>> result = await _uc.listSites();
    if (!mounted) return;
    final List<SiteConfig> sites = result.valueOrNull ?? const <SiteConfig>[];
    _cachedSites = sites;
    setState(() => _sites = sites);
  }

  Future<void> _loadHome(String siteKey) async {
    final HomeContentResult? cached = _cachedHomeBySite[siteKey];
    if (cached != null) {
      // 命中缓存：直接复用，不重复请求（对齐 iOS 静态缓存复用）。
      setState(() {
        _loading = false;
        _error = null;
        _home = cached;
        _siteKey = siteKey;
      });
      if ((cached.list).isNotEmpty) {
        SplashGateMonitor.instance.markHomeReady();
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final Result<HomeContentResult> result = await _uc.homeContent(siteKey);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = result.failureOrNull;
      _home = result.valueOrNull;
      _siteKey = siteKey;
    });
    final HomeContentResult? home = result.valueOrNull;
    if (home != null) {
      _cachedHomeBySite[siteKey] = home;
    }
    // L-壳1 数据门控：切换源后已有可展示内容 → 允许启动页淡出。
    if ((home?.list ?? const <VodItem>[]).isNotEmpty) {
      SplashGateMonitor.instance.markHomeReady();
    }
  }

  /// 回到豆瓣默认内容（A9）。
  void _backToDouban() {
    setState(() {
      _siteKey = null;
      _home = null;
      _error = null;
    });
  }

  Future<void> _switchSource() async {
    if (_sites.isEmpty) {
      VboxToast.show(context, '暂无可用站点，当前为豆瓣推荐');
      await _loadSites();
      if (!mounted || _sites.isEmpty) return;
    }
    final String? picked = await showVboxSourceSheet(
      context,
      sites: _sites,
      selectedKey: _siteKey,
    );
    if (picked == null || !mounted || picked == _siteKey) return;
    await _loadHome(picked);
  }

  @override
  Widget build(BuildContext context) {
    final bool doubanMode = _siteKey == null;
    return Scaffold(
      // 首页顶栏对齐 iOS `MainViews.swift HomeSearchBar`（L918-L997）：
      // 源切换（square.grid.2x2）→ 搜索框 → 豆瓣排行榜（chart.bar.fill）→
      // 观看历史（clock.arrow.circlepath）→ AI 星星（sparkles）；
      // 不用 AppBar，保持与 iOS「内容内顶栏」一致的排布。
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _buildTopBar(context, sourceSelected: !doubanMode),
            Expanded(
              // 对齐 iOS `DoubanHomeView`：首页豆瓣条目点击即 `triggerSearch(title)`
              // 进入搜索页按标题搜索。
              child: doubanMode
                  ? DoubanHomeView(
                      onSubjectTap: (DoubanSubject subject) =>
                          _openSearchForKey(subject.title),
                    )
                  : _buildSiteBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// 首页顶栏（对齐 iOS `HomeSearchBar`）。
  Widget _buildTopBar(BuildContext context, {required bool sourceSelected}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VboxSpacing.sm,
        VboxSpacing.sm,
        VboxSpacing.sm,
        VboxSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          // 多源选择（对齐 iOS `square.grid.2x2`；选中源时高亮绿）。
          _TopBarIcon(
            tooltip: '切换源',
            icon: Icons.grid_view_rounded,
            color: sourceSelected
                ? VboxColors.topBarSourceSelected
                : scheme.onSurface,
            onPressed: _switchSource,
          ),
          Expanded(child: _buildSearchField(context)),
          // 排行榜（对齐 iOS `chart.bar.fill` → DoubanRankingView）。
          _TopBarIcon(
            tooltip: '豆瓣排行榜',
            icon: Icons.bar_chart_rounded,
            onPressed: _openRanking,
          ),
          // 观看历史（对齐 iOS `clock.arrow.circlepath` → WatchHistoryView）。
          _TopBarIcon(
            tooltip: '观看历史',
            icon: Icons.history,
            onPressed: _openHistory,
          ),
          // AI（对齐 iOS `sparkles` → 打开 Lobster-APP 仓库）。
          _TopBarIcon(
            tooltip: 'AI 推荐',
            icon: Icons.auto_awesome,
            color: VboxColors.topBarAiAccent,
            onPressed: _openAi,
          ),
          if (sourceSelected)
            _TopBarIcon(
              tooltip: '返回豆瓣推荐',
              icon: Icons.recommend_outlined,
              onPressed: _backToDouban,
            ),
        ],
      ),
    );
  }

  /// 顶栏搜索框（只读按钮，点击进入搜索页；对齐 iOS `HomeSearchBar` 搜索栏）。
  Widget _buildSearchField(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openSearch,
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: VboxSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: VboxSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.search, size: VboxTypography.s16, color: scheme.outline),
            const SizedBox(width: VboxSpacing.sm),
            Expanded(
              child: Text(
                '搜索影片、剧集',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: VboxTypography.s15,
                  color: scheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SearchPage(initialSiteKey: _siteKey),
      ),
    );
  }

  /// 以关键词进入搜索页并立即搜索（对齐 iOS `settings.triggerSearch(title)`）。
  void _openSearchForKey(String keyword) {
    final String kw = keyword.trim();
    if (kw.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SearchPage(initialKeyword: kw),
      ),
    );
  }

  void _openRanking() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DoubanRankingPage()),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => Scaffold(
          appBar: AppBar(title: const Text('观看历史')),
          body: const HistoryView(),
        ),
      ),
    );
  }

  Future<void> _openAi() async {
    await launchUrl(
      Uri.parse('https://github.com/vbox-Ai/Lobster-APP'),
      mode: LaunchMode.externalApplication,
    );
  }

  Widget _buildSiteBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final Failure? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _retry);
    }
    final HomeContentResult? home = _home;
    final List<VodItem> items = home?.list ?? const <VodItem>[];
    if (items.isEmpty && (home?.classes ?? const <VodCategory>[]).isEmpty) {
      return const _EmptyHint(text: '站点暂无内容\n点击右上角切换源试试');
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.md),
      children: <Widget>[
        if (items.isNotEmpty) _buildCarousel(items),
        if (home?.classes != null && home!.classes!.isNotEmpty)
          _buildCategories(home.classes!),
        if (items.isNotEmpty) _buildPosterSection(items),
      ],
    );
  }

  void _retry() {
    final String? key = _siteKey;
    if (key != null) {
      _loadHome(key);
    } else {
      _loadSites();
    }
  }

  Widget _buildCarousel(List<VodItem> items) {
    final List<VodItem> top = items.take(_Carousel.maxCount).toList();
    return _Carousel(items: top);
  }

  Widget _buildCategories(List<VodCategory> classes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const VboxSectionHeader(title: '分类'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < classes.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: VboxSpacing.sm),
                VboxChip(
                  label: classes[i].typeName,
                  onTap: () => _openCategory(classes[i].typeId),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openCategory(String tid) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CategoryPage(
          initialSiteKey: _siteKey,
          initialTid: tid,
        ),
      ),
    );
  }

  Widget _buildPosterSection(List<VodItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const VboxSectionHeader(title: '推荐'),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: VboxSpacing.md),
            itemBuilder: (BuildContext context, int index) =>
                _posterFromVod(items[index]),
          ),
        ),
      ],
    );
  }

  Widget _posterFromVod(VodItem vod) {
    final String subtitle = <String?>[
      if (vod.vodYear?.isNotEmpty ?? false) vod.vodYear,
      if (vod.vodRemarks?.isNotEmpty ?? false) vod.vodRemarks,
    ].join(' · ');
    return VboxPosterCard(
      title: vod.vodName,
      imageUrl: vod.vodPic,
      subtitle: subtitle.isEmpty ? null : subtitle,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => DetailPage(
              siteKey: _siteKey ?? '',
              vodId: vod.vodId,
              title: vod.vodName,
            ),
          ),
        );
      },
    );
  }
}

/// 首页顶栏图标按钮。
///
/// 对齐 iOS `MainViews.swift HomeSearchBar`（L918-L997）：图标 18、无背景、
/// 可选高亮色（切换源选中绿 / AI 蓝），点击区域紧凑排布。
class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({
    required this.tooltip,
    required this.icon,
    this.color,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ?? Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: resolved),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      ),
    );
  }
}

/// 轮播。
class _Carousel extends StatefulWidget {
  const _Carousel({required this.items});

  static const int maxCount = 5;

  final List<VodItem> items;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 200,
          child: PageView.builder(
            itemCount: widget.items.length,
            onPageChanged: (int i) => setState(() => _page = i),
            itemBuilder: (BuildContext context, int i) {
              final VodItem vod = widget.items[i];
              return Padding(
                padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _CarouselImage(url: vod.vodPic),
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
                            vod.vodName,
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

/// 轮播封面（空地址 → 占位盒）。
class _CarouselImage extends StatelessWidget {
  const _CarouselImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return PlatformAsyncImage(url: url, fit: BoxFit.cover);
  }
}

/// 空态提示。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
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