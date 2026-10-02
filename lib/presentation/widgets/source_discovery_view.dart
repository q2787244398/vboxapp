/// 源发现（单源分类浏览）视图（批次 D · D-07）。
///
/// 对齐 iOS `SourceDiscoveryView`（`vbox/Views/SourceDiscoveryView.swift`）：
/// 顶部源下拉切换 → 分类滑动栏（「推荐」+ 源分类）→ 三列海报网格，分类滚动到
/// 底自动分页；点击海报 push 详情页（`DetailPage`，D-05）。
///
/// 数据通路：`ContentBrowseUseCases.listSites` / `homeContent`（推荐） /
/// `categoryContent`（分类 + 分页），模式分流 CMS / Spider 在用例层完成。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/spider/spider.dart';
import '../../domain/usecases/usecases.dart';
import '../theme/tokens/radii.dart';
import '../theme/tokens/spacing.dart';
import '../theme/tokens/typography.dart';
import '../ui_mode/ui_mode.dart';
import 'adaptive/responsive_grid.dart';
import 'detail_page.dart';
import 'platform_async_image.dart';
import 'vbox/vbox.dart';

/// 源发现视图（嵌入「远程源」页的「源发现」标签）。
class SourceDiscoveryView extends StatefulWidget {
  /// 构造。
  const SourceDiscoveryView({super.key});

  @override
  State<SourceDiscoveryView> createState() => _SourceDiscoveryViewState();
}

class _SourceDiscoveryViewState extends State<SourceDiscoveryView> {
  /// 分页满页判定阈值（对齐卫生契约 §6 默认每页 20）。
  static const int _pageSizeHint = 20;

  late final ContentBrowseUseCases _uc;
  final ScrollController _scroll = ScrollController();

  // 源
  List<SiteConfig> _sites = const <SiteConfig>[];
  String? _siteKey;
  bool _loadingSites = false;
  Failure? _sitesError;

  // 推荐（homeContent）
  List<VodCategory> _categories = const <VodCategory>[];
  List<VodItem> _recommended = const <VodItem>[];

  // 分类内容（categoryContent，分页）
  String? _selectedTid;
  final List<VodItem> _items = <VodItem>[];
  int _page = 0;
  int? _pagecount;
  bool _lastBatchFull = true;

  bool _loading = false;
  bool _loadingMore = false;
  Failure? _error;

  @override
  void initState() {
    super.initState();
    _uc = context.read<ContentBrowseUseCases>();
    _scroll.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_selectedTid != null && _scroll.position.extentAfter < 240) {
      _loadMore();
    }
  }

  bool get _hasMore {
    final int? pc = _pagecount;
    if (pc != null) return _page < pc;
    return _lastBatchFull;
  }

  List<VodItem> get _displayItems =>
      _selectedTid == null ? _recommended : _items;

  // ─────────────── 数据加载 ───────────────

  Future<void> _init() async {
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    final Result<List<SiteConfig>> result = await _uc.listSites();
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() {
        _loadingSites = false;
        _sitesError = failure;
      });
      return;
    }
    final List<SiteConfig> sites = result.valueOrNull ?? const <SiteConfig>[];
    if (sites.isEmpty) {
      setState(() {
        _loadingSites = false;
        _sitesError = const UnknownFailure('无可用站点');
      });
      return;
    }
    setState(() {
      _loadingSites = false;
      _sites = sites;
      _siteKey = sites.first.key;
    });
    await _loadHome();
  }

  Future<void> _loadHome() async {
    final String? siteKey = _siteKey;
    if (siteKey == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _selectedTid = null;
      _categories = const <VodCategory>[];
      _recommended = const <VodItem>[];
      _items.clear();
      _page = 0;
      _pagecount = null;
      _lastBatchFull = true;
    });
    final Result<HomeContentResult> result = await _uc.homeContent(siteKey);
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() {
        _loading = false;
        _error = failure;
      });
      return;
    }
    final HomeContentResult home =
        result.valueOrNull ?? const HomeContentResult();
    setState(() {
      _categories = home.classes ?? const <VodCategory>[];
      _recommended = home.list ?? const <VodItem>[];
      _loading = false;
    });
  }

  Future<void> _selectSite(String? siteKey) async {
    if (siteKey == null || siteKey == _siteKey) return;
    setState(() => _siteKey = siteKey);
    await _loadHome();
  }

  Future<void> _selectTid(String? tid) async {
    if (tid == _selectedTid) return;
    setState(() {
      _selectedTid = tid;
      _items.clear();
      _page = 0;
      _pagecount = null;
      _lastBatchFull = true;
    });
    if (tid == null) return; // 「推荐」直接复用已加载的 _recommended
    await _loadCategory();
  }

  Future<void> _loadCategory() async {
    if (_loading || _loadingMore) return;
    final String? siteKey = _siteKey;
    final String? tid = _selectedTid;
    if (siteKey == null || tid == null) return;

    final bool initial = _page == 0 && _items.isEmpty;
    setState(() {
      if (initial) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });

    final int nextPage = _page + 1;
    final Result<CategoryContentResult> result =
        await _uc.categoryContent(siteKey, tid: tid, page: nextPage);
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (initial) _error = failure;
      });
      if (!initial) _toast('加载失败：$failure');
      return;
    }
    final CategoryContentResult content =
        result.valueOrNull ?? const CategoryContentResult();
    final List<VodItem> batch = content.list ?? const <VodItem>[];
    setState(() {
      if (initial) {
        _items
          ..clear()
          ..addAll(batch);
      } else {
        _items.addAll(batch);
      }
      _page = nextPage;
      _pagecount = content.pagecount;
      _lastBatchFull = batch.length >= _pageSizeHint;
      _loading = false;
      _loadingMore = false;
    });
  }

  Future<void> _loadMore() async {
    if (_selectedTid == null || !_hasMore || _loading || _loadingMore) return;
    await _loadCategory();
  }

  Future<void> _retry() async {
    if (_selectedTid == null) {
      await _loadHome();
    } else {
      await _loadCategory();
    }
  }

  void _openDetail(VodItem vod) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DetailPage(
          siteKey: _siteKey ?? '',
          vodId: vod.vodId,
          title: vod.vodName,
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─────────────── UI ───────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildSourceBar(),
        _buildCategoryBar(),
        const SizedBox(height: VboxSpacing.xs),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSourceBar() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: VboxSpacing.symmetric(
          horizontal: VboxSpacing.lg, vertical: VboxSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(Icons.language, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: VboxSpacing.sm),
          Text(
            '源',
            style: TextStyle(
              fontSize: VboxTypography.s13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: VboxSpacing.xs),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _siteKey,
                isExpanded: true,
                isDense: true,
                onChanged: _selectSite,
                items: <DropdownMenuItem<String>>[
                  for (final SiteConfig s in _sites)
                    DropdownMenuItem<String>(
                      value: s.key,
                      child: Text(
                        s.name.isEmpty ? s.key : s.name,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildCategoryBar() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
        children: <Widget>[
          VboxChip(
            label: '推荐',
            selected: _selectedTid == null,
            onTap: () => _selectTid(null),
          ),
          for (int i = 0; i < _categories.length; i++) ...<Widget>[
            const SizedBox(width: VboxSpacing.sm),
            VboxChip(
              label: _categories[i].typeName,
              selected: _selectedTid == _categories[i].typeId,
              onTap: () => _selectTid(_categories[i].typeId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingSites) return const Center(child: CircularProgressIndicator());
    final Failure? sitesError = _sitesError;
    if (sitesError != null) {
      return _ErrorRetry(message: '$sitesError', onRetry: _init);
    }
    if (_sites.isEmpty) {
      return const _EmptyHint(text: '没有可浏览的站点\n请先在「订阅源」添加可用源');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Failure? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _retry);
    }
    if (_displayItems.isEmpty) {
      return const _EmptyHint(text: '暂无内容\n切换源或分类试试');
    }
    return _buildGrid();
  }

  Widget _buildGrid() {
    final UiFormController formController = context.watch<UiFormController>();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final UiForm form = formController.resolveAt(
          size: MediaQuery.sizeOf(context),
          orientation: MediaQuery.orientationOf(context),
        );
        const double paddingH = VboxSpacing.lg;
        const double spacing = VboxSpacing.md;
        final double availWidth = constraints.maxWidth - paddingH * 2;
        final int columns = ResponsiveGrid.columnsFor(
          form: form,
          width: constraints.maxWidth,
        );
        final double cellWidth =
            (availWidth - spacing * (columns - 1)) / columns;
        final double cellExtent = cellWidth * 1.5 + 44;

        final bool paging = _selectedTid != null;
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(
              paddingH, VboxSpacing.sm, paddingH, VboxSpacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: cellExtent,
          ),
          itemCount: _displayItems.length +
              ((paging && _loadingMore) ? 1 : 0),
          itemBuilder: (BuildContext context, int index) {
            if (index >= _displayItems.length) {
              return const Center(child: CircularProgressIndicator());
            }
            return _posterFromVod(_displayItems[index]);
          },
        );
      },
    );
  }

  Widget _posterFromVod(VodItem vod) {
    final String subtitle = <String?>[
      if (vod.vodYear?.isNotEmpty ?? false) vod.vodYear,
      if (vod.vodRemarks?.isNotEmpty ?? false) vod.vodRemarks,
    ].join(' · ');
    return _PosterCell(
      title: vod.vodName,
      imageUrl: vod.vodPic,
      subtitle: subtitle.isEmpty ? null : subtitle,
      onTap: () => _openDetail(vod),
    );
  }
}

/// 网格海报单元（2:3 封面 + 单行标题 + 可选副标题）。
class _PosterCell extends StatelessWidget {
  const _PosterCell({
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: VboxRadii.card,
              child: SizedBox.expand(
                child: PlatformAsyncImage(
                  url: imageUrl,
                  fit: BoxFit.cover,
                  placeholderColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          const SizedBox(height: VboxSpacing.sm),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: VboxTypography.s13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: VboxTypography.s11,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
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