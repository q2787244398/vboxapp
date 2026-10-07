/// 分类网格（批次 D · D-06）。
///
/// 每源三要素：源下拉（AppBar 下拉）+ 分类胶囊（含「全部」）+ 海报网格（三列起，
/// 列数随形态自适应），滚动到底自动分页。数据通路：
/// `ContentBrowseUseCases.listSites` / `categories` / `categoryContent`
/// （模式分流 CMS / Spider 在用例层完成），点击海报 push 详情页。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/spider/spider.dart';
import '../../../domain/usecases/usecases.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/adaptive/responsive_grid.dart';
import '../../widgets/detail_page.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import '../home/source_sheet.dart';

/// 源类型徽标配色（对齐 iOS `SourceDiscoveryView.categoryBadgeColor`：
/// 网盘蓝 / 其它按类型区分）。
Color categoryBadgeColor(SiteConfig site) {
  switch (site.categoryLabel) {
    case '网盘':
      return const Color(0xFF2563EB);
    case 'API':
      return const Color(0xFF16A34A);
    case '站源':
      return const Color(0xFFEA580C);
    case 'JS':
      return const Color(0xFF7C3AED);
    case '论坛':
      return const Color(0xFF0891B2);
  }
  return VboxColors.skinPrimaryRose;
}

/// 分类浏览页。
class CategoryPage extends StatefulWidget {
  /// 构造。
  const CategoryPage({super.key, this.initialSiteKey, this.initialTid});

  /// 初始站点（缺省选中首个可用站点）。
  final String? initialSiteKey;

  /// 初始分类（缺省「全部」）。
  final String? initialTid;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  /// 分页满页判定阈值（对齐卫生契约 §6 默认每页 20）。
  static const int _pageSizeHint = 20;

  late final ContentBrowseUseCases _uc;
  final ScrollController _scroll = ScrollController();

  List<SiteConfig>? _sites;
  List<VodCategory>? _categories;
  String? _siteKey;
  String? _tid;
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
    if (_scroll.position.extentAfter < 240) {
      _loadMore();
    }
  }

  bool get _hasMore {
    final int? pc = _pagecount;
    if (pc != null) return _page < pc;
    return _lastBatchFull;
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
    final String initial = widget.initialSiteKey ?? '';
    final SiteConfig target = sites.firstWhere(
      (SiteConfig s) => s.key == initial,
      orElse: () => sites.first,
    );
    await _loadSite(target.key);
  }

  Future<void> _loadSite(String siteKey) async {
    setState(() {
      _siteKey = siteKey;
      _loading = true;
      _error = null;
      _categories = null;
      _items.clear();
      _page = 0;
      _pagecount = null;
      _lastBatchFull = true;
    });
    final Result<List<VodCategory>> cats = await _uc.categories(siteKey);
    if (!mounted) return;
    final Failure? catFailure = cats.failureOrNull;
    if (catFailure != null) {
      setState(() {
        _loading = false;
        _error = catFailure;
      });
      return;
    }
    final List<VodCategory> list = cats.valueOrNull ?? const <VodCategory>[];
    final String? requestedTid = widget.initialTid;
    final String? tid = (requestedTid != null && requestedTid.isNotEmpty &&
            list.any((VodCategory c) => c.typeId == requestedTid))
        ? requestedTid
        : null;
    setState(() {
      _categories = list;
      _tid = tid;
      _loading = false; // 分类已就绪；正文 loading 交由 _loadCategory 接管
    });
    await _loadCategory();
  }

  Future<void> _selectCategory(String? tid) async {
    if (tid == _tid) return;
    setState(() {
      _tid = tid;
      _items.clear();
      _page = 0;
      _pagecount = null;
      _lastBatchFull = true;
    });
    await _loadCategory();
  }

  Future<void> _loadCategory() async {
    if (_loading || _loadingMore) return;
    final String? siteKey = _siteKey;
    if (siteKey == null) return;

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
    final Result<CategoryContentResult> result = await _uc.categoryContent(
      siteKey,
      tid: _tid,
      page: nextPage,
    );
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
    if (!_hasMore || _loading || _loadingMore) return;
    await _loadCategory();
  }

  void _retry() async {
    final String? key = _siteKey;
    if (key != null) {
      await _loadSite(key);
    } else {
      await _init();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 对齐 iOS `SourceDiscoveryView.topBar`：返回 + 源名下拉 + 类型徽标，
      // 不用 AppBar（源切换走左上角小竖长条浮层，与首页一致）。
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _buildTopBar(context),
            _buildCategoryPills(),
            const SizedBox(height: VboxSpacing.xs),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  /// 顶部栏（对齐 iOS `SourceDiscoveryView.topBar` L342-L381）。
  Widget _buildTopBar(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SiteConfig? current = _currentSite();
    final String name = (current != null && current.name.isNotEmpty)
        ? current.name
        : (current?.key ?? '分类');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          // 返回（对齐 iOS `chevron.left`，32x32）。
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                Icons.chevron_left,
                size: 22,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 源名 + 下拉箭头 → 打开左上角切换源浮层。
          InkWell(
            onTap: _switchSource,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VboxTypography.s16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const Spacer(),
          // 源类型标签（对齐 iOS `source.category.displayName` 胶囊）。
          if (current != null) _buildCategoryBadge(context, current),
        ],
      ),
    );
  }

  SiteConfig? _currentSite() {
    final List<SiteConfig>? sites = _sites;
    final String? key = _siteKey;
    if (sites == null || key == null) return null;
    for (final SiteConfig s in sites) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// 类型徽标（对齐 iOS `categoryBadgeColor` 胶囊）。
  Widget _buildCategoryBadge(BuildContext context, SiteConfig site) {
    final Color color = categoryBadgeColor(site);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        site.categoryLabel,
        style: TextStyle(
          fontSize: VboxTypography.s11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  /// 打开左上角小竖长条切换源浮层（对齐 iOS `showSourceDropdown`）。
  Future<void> _switchSource() async {
    final List<SiteConfig>? sites = _sites;
    if (sites == null || sites.isEmpty) return;
    final String? picked = await showVboxSourceSheet(
      context,
      sites: sites,
      selectedKey: _siteKey,
    );
    if (picked == null || !mounted || picked == _siteKey) return;
    await _loadSite(picked);
  }

  Widget _buildCategoryPills() {
    final List<VodCategory>? categories = _categories;
    if (categories == null || categories.isEmpty) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
      child: Row(
        children: <Widget>[
          VboxChip(
            label: '全部',
            selected: _tid == null,
            onTap: () => _selectCategory(null),
          ),
          for (int i = 0; i < categories.length; i++) ...<Widget>[
            const SizedBox(width: VboxSpacing.sm),
            VboxChip(
              label: categories[i].typeName,
              selected: _tid == categories[i].typeId,
              onTap: () => _selectCategory(categories[i].typeId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Failure? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _retry);
    }
    if (_items.isEmpty) {
      return const _EmptyHint(text: '该分类暂无内容\n切换分类或源试试');
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
          itemCount: _items.length + (_loadingMore ? 1 : 0),
          itemBuilder: (BuildContext context, int index) {
            if (index >= _items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            return _posterFromVod(_items[index]);
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