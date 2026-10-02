/// 首页内容浏览（批次 D · D-01）。
///
/// 每源三区块：轮播（首条若干海报）+ 分类胶囊 + 横向海报列表；顶部切换源入口
/// （底部浮层列出全部站点）。数据通路：`ContentBrowseUseCases.listSites` +
/// `homeContent`（模式分流 CMS / Spider 在用例层完成），点击海报 push 详情页。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/spider/spider.dart';
import '../../../domain/usecases/usecases.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/detail_page.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import '../category/category_page.dart';
import '../search/search_page.dart';
import 'source_sheet.dart';

/// 首页（内容浏览）。默认选中首个可用站点，切换源后重载。
class VboxHomePage extends StatefulWidget {
  /// 构造。
  const VboxHomePage({super.key});

  @override
  State<VboxHomePage> createState() => _VboxHomePageState();
}

class _VboxHomePageState extends State<VboxHomePage> {
  late final ContentBrowseUseCases _uc;

  List<SiteConfig>? _sites;
  String? _siteKey;
  HomeContentResult? _home;
  Failure? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _uc = context.read<ContentBrowseUseCases>();
    _init();
  }

  Future<void> _init() async {
    final Result<List<SiteConfig>> result = await _uc.listSites();
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() {
        _loading = false;
        _error = failure;
      });
      return;
    }
    final List<SiteConfig> sites = result.valueOrNull ?? const <SiteConfig>[];
    if (sites.isEmpty) {
      setState(() {
        _loading = false;
        _error = const UnknownFailure('无可用站点');
      });
      return;
    }
    _sites = sites;
    await _loadHome(sites.first.key);
  }

  Future<void> _loadHome(String siteKey) async {
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
  }

  Future<void> _switchSource() async {
    final List<SiteConfig>? sites = _sites;
    if (sites == null || sites.isEmpty) return;
    final String? picked = await showVboxSourceSheet(
      context,
      sites: sites,
      selectedKey: _siteKey,
    );
    if (picked == null || !mounted || picked == _siteKey) return;
    await _loadHome(picked);
  }

  SiteConfig? get _currentSite {
    final List<SiteConfig>? sites = _sites;
    if (sites == null) return null;
    for (final SiteConfig s in sites) {
      if (s.key == _siteKey) return s;
    }
    return sites.isNotEmpty ? sites.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final SiteConfig? site = _currentSite;
    return Scaffold(
      appBar: AppBar(
        title: Text(site == null || site.name.isEmpty ? '首页' : site.name),
        actions: <Widget>[
          IconButton(
            tooltip: '切换源',
            icon: const Icon(Icons.layers_outlined),
            onPressed: _switchSource,
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => SearchPage(
                    initialSiteKey: _siteKey,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
      _init();
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