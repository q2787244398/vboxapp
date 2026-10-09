/// 豆瓣分类浏览（批次 D · D-03；UI-A1 扩展：快捷分类详情弹层）。
///
/// 分类胶囊（电影 / 剧集 / 综艺 / 动漫 / 纪录片）+ 筛选胶囊（排序 / 类型 / 年代 /
/// 平台 / 地区）+ 响应式海报网格（滚动到底分页）。数据通路：
/// [DoubanUseCases.category]（客户端过滤 + 排序，对齐 iOS）。仅浏览。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/douban/douban_models.dart';
import '../../../domain/usecases/douban_usecases.dart';
import '../../theme/tokens/spacing.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/adaptive/responsive_grid.dart';
import '../../widgets/vbox/vbox.dart';
import 'douban_widgets.dart';

/// 豆瓣分类浏览页。
class DoubanCategoryPage extends StatefulWidget {
  /// 构造。
  ///
  /// [initialCategory]：初始分类（首页快捷分类胶囊入口用；null 取
  /// [DoubanCategory.all] 首项）。
  /// [embedded]：嵌入模式（对齐 iOS `CategoryDetailView` 以 pageSheet 弹出的
  /// 形态，DoubanHomeView.swift L32-L93）：无 Scaffold / AppBar，顶部为
  /// 「找xx」大标题。
  const DoubanCategoryPage({
    super.key,
    this.initialCategory,
    this.embedded = false,
  });

  /// 初始分类。
  final DoubanCategory? initialCategory;

  /// 是否嵌入模式（sheet 弹层内容）。
  final bool embedded;

  @override
  State<DoubanCategoryPage> createState() => _DoubanCategoryPageState();
}

class _DoubanCategoryPageState extends State<DoubanCategoryPage> {
  late final DoubanUseCases _uc;
  final ScrollController _scroll = ScrollController();

  late DoubanCategory _category =
      widget.initialCategory ?? DoubanCategory.all.first;
  DoubanFilterParams _filters = const DoubanFilterParams();

  final List<DoubanSubject> _items = <DoubanSubject>[];
  int _page = 0;
  bool _lastBatchFull = true;
  bool _loading = false;
  bool _loadingMore = false;
  Failure? _error;

  @override
  void initState() {
    super.initState();
    _uc = context.read<DoubanUseCases>();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 240) _loadMore();
  }

  bool get _hasMore => _lastBatchFull;

  Future<void> _selectCategory(DoubanCategory category) async {
    if (category.type == _category.type) return;
    _category = category;
    _filters = const DoubanFilterParams();
    await _load(reset: true);
  }

  Future<void> _updateFilters(DoubanFilterParams next) async {
    if (identical(next, _filters)) return;
    _filters = next;
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || _loadingMore) return;
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _items.clear();
        _page = 0;
        _lastBatchFull = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    final int nextPage = _page + 1;
    final Result<List<DoubanSubject>> result =
        await _uc.category(_category, _filters, page: nextPage);
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = failure;
      });
      if (!reset) _toast('加载失败：$failure');
      return;
    }
    final List<DoubanSubject> batch =
        result.valueOrNull ?? const <DoubanSubject>[];
    setState(() {
      if (reset) {
        _items
          ..clear()
          ..addAll(batch);
      } else {
        _items.addAll(batch);
      }
      _page = nextPage;
      _lastBatchFull = batch.length >= DoubanUseCases.pageSize;
      _loading = false;
      _loadingMore = false;
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading || _loadingMore) return;
    await _load(reset: false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // 对齐 iOS `CategoryDetailView` pageSheet 形态（L32-L93）：
      // 顶部「找xx」大标题 + 筛选区 + 内容区，无 AppBar。
      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VboxSpacing.lg,
              VboxSpacing.sm,
              VboxSpacing.lg,
              VboxSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '找${_category.name}',
                style: const TextStyle(
                  // iOS 20pt bold；令牌档位就近取 18（R-3 集合无 20）。
                  fontSize: VboxTypography.s18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          _buildFilterPanel(),
          Expanded(child: _buildBody()),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('豆瓣分类')),
      body: Column(
        children: <Widget>[
          _buildFilterPanel(),
          const SizedBox(height: VboxSpacing.xs),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PillRow(
          values: DoubanCategory.all
              .map((DoubanCategory c) => c.name)
              .toList(growable: false),
          selected: _category.name,
          onTap: (String name) => _selectCategory(
            DoubanCategory.all.firstWhere((DoubanCategory c) => c.name == name),
          ),
        ),
        _PillRow(
          values: DoubanSortType.values
              .map((DoubanSortType s) => s.displayName)
              .toList(growable: false),
          selected: _filters.sort.displayName,
          onTap: (String name) => _updateFilters(
            _filters.copyWith(
              sort: DoubanSortType.values
                  .firstWhere((DoubanSortType s) => s.displayName == name),
            ),
          ),
        ),
        _PillRow(
          values: _category.genres,
          selected: _filters.genre ?? '全部',
          onTap: (String value) => _updateFilters(
            _filters.copyWith(genre: value == '全部' ? null : value),
          ),
        ),
        _PillRow(
          values: _category.years,
          selected: _filters.year ?? '全部',
          onTap: (String value) => _updateFilters(
            _filters.copyWith(year: value == '全部' ? null : value),
          ),
        ),
        _PillRow(
          values: _category.regions,
          selected: _filters.region ?? '全部',
          onTap: (String value) => _updateFilters(
            _filters.copyWith(region: value == '全部' ? null : value),
          ),
        ),
        _PillRow(
          values: _category.platforms,
          selected: _filters.platform ?? '全部',
          onTap: (String value) => _updateFilters(
            _filters.copyWith(platform: value == '全部' ? null : value),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Failure? error = _error;
    if (error != null) {
      return DoubanErrorRetry(message: '$error', onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return const DoubanEmptyHint(text: '该分类暂无内容\n切换筛选条件试试');
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
            return DoubanSubjectCard(subject: _items[index]);
          },
        );
      },
    );
  }
}

/// 单行胶囊筛选（横向滚动，等值点击忽略）。
class _PillRow extends StatelessWidget {
  const _PillRow({
    required this.values,
    required this.selected,
    required this.onTap,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: VboxSpacing.symmetric(
        horizontal: VboxSpacing.lg,
        vertical: VboxSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < values.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: VboxSpacing.sm),
            VboxChip(
              label: values[i],
              dense: true,
              selected: values[i] == selected,
              onTap: () => onTap(values[i]),
            ),
          ],
        ],
      ),
    );
  }
}