/// 短剧页（批次 D · D-04）。
///
/// 对齐 iOS `ShortDramaView` / `ShortDramaService`：自动扫描所有 VOD 源中的
/// 短剧分类（分类名命中关键词）→ 顶部源标签滚动条切源 → 三列海报网格；点击
/// 卡片 push 详情页（`DetailPage`，D-05 扩展）。
///
/// 数据通路：`ContentBrowseUseCases.listSites` / `categories` / `categoryContent`
/// / `searchContent`（模式分流 CMS / Spider 在用例层完成）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/spider/spider.dart';
import '../../../domain/usecases/usecases.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/adaptive/responsive_grid.dart';
import '../../widgets/detail_page.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';

/// 短剧分类关键词（对齐 iOS `ShortDramaService.dramaKeywords`）。
const List<String> kShortDramaKeywords = <String>[
  '短剧', '剧场', '网剧', '微短剧', '爽文短剧', '擦边短剧', '短剧大全',
  '竖屏剧', '小剧场', '迷你剧', '微剧', '短视频剧', '短片剧',
];

/// 是否为短剧分类名。
bool looksLikeShortDramaCategory(String typeName) =>
    kShortDramaKeywords.any(typeName.contains);

/// 短剧源（站点 + 命中的短剧分类）。
class ShortDramaSource {
  /// 构造。
  const ShortDramaSource({
    required this.id,
    required this.name,
    required this.siteKey,
    required this.categoryId,
    required this.categoryName,
  });

  /// 唯一标识。
  final String id;

  /// 站点名（源标签名）。
  final String name;

  /// 站点 key（数据通路用）。
  final String siteKey;

  /// 分类 ID。
  final String categoryId;

  /// 分类名。
  final String categoryName;

  /// 展示名（对齐 iOS：`name(categoryName)`）。
  String get displayName => '$name($categoryName)';
}

/// 短剧页（列表 + 搜索）。
class ShortDramaPage extends StatefulWidget {
  /// 构造。
  const ShortDramaPage({super.key});

  @override
  State<ShortDramaPage> createState() => _ShortDramaPageState();
}

class _ShortDramaPageState extends State<ShortDramaPage> {
  late final ContentBrowseUseCases _uc;
  final TextEditingController _controller = TextEditingController();

  bool _scanning = false;
  Failure? _error;
  List<ShortDramaSource> _sources = const <ShortDramaSource>[];
  String? _selectedSourceId;

  bool _loading = false;
  bool _loadingMore = false;
  int _page = 0;
  int? _pagecount;
  bool _lastBatchFull = true;
  final List<VodItem> _items = <VodItem>[];

  bool _searching = false;
  bool _searchLoading = false;
  Failure? _searchError;
  final List<VodItem> _searchResults = <VodItem>[];

  @override
  void initState() {
    super.initState();
    _uc = context.read<ContentBrowseUseCases>();
    _scan();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ShortDramaSource? get _selectedSource {
    for (final ShortDramaSource s in _sources) {
      if (s.id == _selectedSourceId) return s;
    }
    return _sources.isEmpty ? null : _sources.first;
  }

  // ─────────────── 源扫描 ───────────────

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    final Result<List<SiteConfig>> result = await _uc.listSites();
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() {
        _scanning = false;
        _error = failure;
      });
      return;
    }
    final List<SiteConfig> sites = result.valueOrNull ?? const <SiteConfig>[];
    if (sites.isEmpty) {
      setState(() {
        _scanning = false;
        _error = const UnknownFailure('无可用站点');
      });
      return;
    }

    // 并发扫描各站点分类（单站失败不影响整体）。
    final List<ShortDramaSource> found = <ShortDramaSource>[];
    final List<Future<void>> tasks = <Future<void>>[];
    final Set<String> seenIds = <String>{};
    for (final SiteConfig site in sites) {
      tasks.add(_scanSite(site, found, seenIds));
    }
    await Future.wait(tasks);

    if (!mounted) return;
    found.sort((ShortDramaSource a, ShortDramaSource b) =>
        a.name.compareTo(b.name));
    setState(() {
      _scanning = false;
      _sources = List<ShortDramaSource>.unmodifiable(found);
      _selectedSourceId = found.isEmpty ? null : found.first.id;
    });
    if (found.isNotEmpty) {
      await _load(reset: true);
    }
  }

  Future<void> _scanSite(
    SiteConfig site,
    List<ShortDramaSource> out,
    Set<String> seenIds,
  ) async {
    try {
      final Result<List<VodCategory>> r = await _uc.categories(site.key);
      final Failure? failure = r.failureOrNull;
      if (failure != null) return;
      for (final VodCategory cat in r.valueOrNull ?? const <VodCategory>[]) {
        if (!looksLikeShortDramaCategory(cat.typeName)) continue;
        final String id = '${site.key}_${cat.typeId}';
        if (!seenIds.add(id)) continue;
        out.add(ShortDramaSource(
          id: id,
          name: site.name.isEmpty ? site.key : site.name,
          siteKey: site.key,
          categoryId: cat.typeId,
          categoryName: cat.typeName,
        ));
      }
    } catch (_) {
      // 单站扫描失败静默跳过（对齐 iOS 容错）。
    }
  }

  // ─────────────── 列表加载 ───────────────

  Future<void> _refresh() async {
    if (_sources.isEmpty) {
      await _scan();
      return;
    }
    await _load(reset: true);
  }

  Future<void> _selectSource(String id) async {
    if (id == _selectedSourceId) return;
    setState(() {
      _selectedSourceId = id;
      _exitSearch();
    });
    await _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || _loadingMore) return;
    final ShortDramaSource? source = _selectedSource;
    if (source == null) return;

    if (reset) {
      _page = 0;
      _pagecount = null;
      _lastBatchFull = true;
      _items.clear();
    }

    final bool initial = _items.isEmpty;
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
      source.siteKey,
      tid: source.categoryId,
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
      _items.addAll(batch);
      _page = nextPage;
      _pagecount = content.pagecount;
      _lastBatchFull = batch.length >= 20;
      _loading = false;
      _loadingMore = false;
    });
  }

  bool get _hasMore {
    final int? pc = _pagecount;
    if (pc != null) return _page < pc;
    return _lastBatchFull;
  }

  // ─────────────── 搜索 ───────────────

  Future<void> _submitSearch(String raw) async {
    final String keyword = raw.trim();
    if (keyword.isEmpty) return;
    final ShortDramaSource? source = _selectedSource;
    if (source == null) return;
    setState(() {
      _searching = true;
      _searchLoading = true;
      _searchError = null;
      _searchResults.clear();
    });
    final Result<SearchContentResult> result =
        await _uc.searchContent(source.siteKey, keyword);
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    setState(() {
      _searchLoading = false;
      _searchError = failure;
      if (failure == null) {
        _searchResults
          ..clear()
          ..addAll(result.valueOrNull?.list ?? const <VodItem>[]);
      }
    });
  }

  void _exitSearch() {
    _controller.clear();
    setState(() {
      _searching = false;
      _searchLoading = false;
      _searchError = null;
      _searchResults.clear();
    });
  }

  // ─────────────── 明细跳转 ───────────────

  void _openDetail(VodItem vod) {
    final ShortDramaSource? source = _selectedSource;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DetailPage(
          siteKey: source?.siteKey ?? '',
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
    return Scaffold(
      appBar: AppBar(title: const Text('短剧')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSearchBar(),
          if (_sources.isNotEmpty) _buildSourceTabs(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VboxSpacing.lg, VboxSpacing.xs, VboxSpacing.lg, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 40,
              padding: VboxSpacing.symmetric(horizontal: VboxSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: VboxRadii.badge,
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search, size: 18, color: scheme.outline),
                  const SizedBox(width: VboxSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: '搜索短剧',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: VboxTypography.s15),
                      onSubmitted: _submitSearch,
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.cancel, size: 16, color: scheme.outline),
                      onPressed: () {
                        _controller.clear();
                        _exitSearch();
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: VboxSpacing.sm),
          _buildSourceButton(),
        ],
      ),
    );
  }

  Widget _buildSourceButton() {
    final ShortDramaSource? source = _selectedSource;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: VboxRadii.button,
      onTap: () => _showSourcePicker(),
      child: Container(
        padding: VboxSpacing.symmetric(
            horizontal: VboxSpacing.md, vertical: VboxSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: VboxRadii.button,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.filter_list, size: 14, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              source?.name ?? '选择源',
              style: TextStyle(fontSize: VboxTypography.s13, color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSourcePicker() async {
    if (_sources.isEmpty) return;
    final String current = _selectedSourceId ?? '';
    final ShortDramaSource? picked = await showModalBottomSheet<ShortDramaSource>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => _SourcePickerSheet(
        sources: _sources,
        selectedId: current,
      ),
    );
    if (picked != null && picked.id != _selectedSourceId) {
      await _selectSource(picked.id);
    }
  }

  Widget _buildSourceTabs() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
        itemCount: _sources.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: VboxSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final ShortDramaSource s = _sources[index];
          return VboxChip(
            label: s.displayName,
            dense: true,
            selected: s.id == _selectedSourceId,
            onTap: () => _selectSource(s.id),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_searching) return _buildSearchResults();
    if (_scanning) return const Center(child: CircularProgressIndicator());
    final Failure? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _refresh);
    }
    if (_sources.isEmpty) {
      return const _EmptyHint(text: '未检测到短剧源\n请在设置中添加包含短剧的订阅源');
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const _EmptyHint(text: '该短剧源暂无内容');
    }
    return _buildGrid();
  }

  Widget _buildSearchResults() {
    if (_searchLoading) return const Center(child: CircularProgressIndicator());
    final Failure? error = _searchError;
    if (error != null) {
      return _ErrorRetry(
        message: '$error',
        onRetry: () => _submitSearch(_controller.text),
      );
    }
    if (_searchResults.isEmpty) {
      return const _EmptyHint(text: '没有找到相关短剧\n换个关键词试试');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.sm),
      itemCount: _searchResults.length,
      itemBuilder: (BuildContext context, int index) {
        final VodItem vod = _searchResults[index];
        return _DramaListRow(
          vod: vod,
          sourceName: _selectedSource?.name,
          onTap: () => _openDetail(vod),
        );
      },
    );
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

        final Widget grid = GridView.builder(
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
            final VodItem vod = _items[index];
            return _DramaCard(
              vod: vod,
              sourceName: _selectedSource?.name,
              onTap: () => _openDetail(vod),
            );
          },
        );

        if (_hasMore) {
          return NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              if (n.metrics.extentAfter < 240) _loadMore();
              return false;
            },
            child: grid,
          );
        }
        return grid;
      },
    );
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading || _loadingMore) return;
    await _load();
  }
}

/// 短剧海报卡（封面 + 集数角标 + 标题 + 来源·集数）。
class _DramaCard extends StatelessWidget {
  const _DramaCard({required this.vod, this.sourceName, this.onTap});

  final VodItem vod;
  final String? sourceName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String remarks = vod.vodRemarks?.trim() ?? '';
    final String subtitle = <String?>[
      if (sourceName != null && sourceName!.isNotEmpty) sourceName,
      if (remarks.isNotEmpty) remarks,
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: VboxRadii.card,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  PlatformAsyncImage(
                    url: vod.vodPic,
                    fit: BoxFit.cover,
                    placeholderColor: scheme.surfaceContainerHighest,
                  ),
                  if (remarks.isNotEmpty)
                    Positioned(
                      left: VboxSpacing.sm,
                      top: VboxSpacing.sm,
                      child: Container(
                        padding: VboxSpacing.symmetric(
                            horizontal: VboxSpacing.sm, vertical: VboxSpacing.xs),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.60),
                          borderRadius: VboxRadii.badge,
                        ),
                        child: Text(
                          remarks,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: VboxTypography.s11,
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
          const SizedBox(height: VboxSpacing.sm),
          Text(
            vod.vodName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: VboxTypography.s13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
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

/// 搜索结果行（缩略图 + 标题 + 备注）。
class _DramaListRow extends StatelessWidget {
  const _DramaListRow({required this.vod, this.sourceName, this.onTap});

  final VodItem vod;
  final String? sourceName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String subtitle = <String?>[
      if (sourceName != null && sourceName!.isNotEmpty) sourceName,
      if (vod.vodRemarks?.isNotEmpty ?? false) vod.vodRemarks,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: VboxSpacing.symmetric(
            horizontal: VboxSpacing.lg, vertical: VboxSpacing.sm),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: VboxRadii.button,
              child: SizedBox(
                width: 68,
                height: 92,
                child: PlatformAsyncImage(url: vod.vodPic, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: VboxSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    vod.vodName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VboxTypography.s14,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: VboxSpacing.xs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: VboxTypography.s11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 源选择浮层。
class _SourcePickerSheet extends StatelessWidget {
  const _SourcePickerSheet({required this.sources, required this.selectedId});

  final List<ShortDramaSource> sources;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: sources.length,
          itemBuilder: (BuildContext context, int index) {
            final ShortDramaSource s = sources[index];
            final bool selected = s.id == selectedId;
            return ListTile(
              title: Text(s.displayName),
              trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
              selected: selected,
              onTap: () => Navigator.of(context).pop(s),
            );
          },
        ),
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