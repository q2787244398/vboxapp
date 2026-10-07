/// 搜索页（批次 D · D-02）。
///
/// 空态：搜索历史（历史 capsulas + 清空）+ 榜单（当前源首页内容取前 N 条）。
/// 结果态：左源列表（横屏竖排 / 竖屏横滑）+ 结果卡（缩略图 + 标题 + 备注）。
/// 数据通路：`ContentBrowseUseCases.listSites` / `searchContent` / `homeContent`
/// + `SearchHistoryUseCases.recent` / `add` / `clear`，点击结果卡 push 详情页。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/douban/douban_models.dart';
import '../../../domain/entities/spider/spider.dart';
import '../../../domain/usecases/usecases.dart';
import '../../../platform/spider/spider.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/detail_page.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import '../douban/douban_ranking_page.dart';

/// 搜索页。
class SearchPage extends StatefulWidget {
  /// 构造。
  const SearchPage({super.key, this.initialSiteKey});

  /// 初始站点（缺省选中首个可用站点）。
  final String? initialSiteKey;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final ContentBrowseUseCases _uc;
  late final SearchHistoryUseCases _history;

  /// 豆瓣用例（空搜索页「豆瓣榜单」数据源）；未注入时为 null（测试环境无豆瓣）。
  DoubanUseCases? _douban;

  /// 附加结果源（S-设2 占源并列 / S-设3 腾讯原生 / Wave D 兜底切片源）；
  /// 缺省注入时为空（测试环境）。
  ZhanyuanSearchUseCases? _zhanyuan;
  TencentVideoNativeSpider? _tencent;
  SourceGovernanceUseCases? _governance;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<SiteConfig>? _sites;
  String? _siteKey;
  List<String> _historyWords = const <String>[];

  /// 空搜索页「豆瓣榜单」栏目标签（标签名 → collectionId），对齐 iOS
  /// `MainViews.swift SearchView.doubanTabs`（L1357）。
  static const List<(String, String)> _doubanTabs = DoubanUseCases.searchTabs;

  /// 当前选中的豆瓣栏目标签下标。
  int _doubanTab = 0;

  /// 豆瓣榜单数据加载中（对齐 iOS `doubanLoading`）。
  bool _doubanLoading = false;

  /// 豆瓣榜单按栏目缓存（对齐 iOS `doubanSubjects[tabName]`，切回不重复请求）。
  final Map<String, List<DoubanSubject>> _doubanCache =
      <String, List<DoubanSubject>>{};

  bool _loading = false;
  Failure? _error;
  bool _searched = false;
  final List<VodItem> _results = <VodItem>[];

  @override
  void initState() {
    super.initState();
    _uc = context.read<ContentBrowseUseCases>();
    _history = context.read<SearchHistoryUseCases>();
    _douban = _maybeRead<DoubanUseCases>(context);
    _zhanyuan = _maybeRead<ZhanyuanSearchUseCases>(context);
    _tencent = _maybeRead<TencentVideoNativeSpider>(context);
    _governance = _maybeRead<SourceGovernanceUseCases>(context);
    _init();
  }

  /// 读取可选 Provider（未注入返回 null，便于 widget 测试无附加源运行）。
  T? _maybeRead<T extends Object>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadHistory();
    await _loadDouban();
    final Result<List<SiteConfig>> result = await _uc.listSites();
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    final List<SiteConfig> sites = result.valueOrNull ?? const <SiteConfig>[];
    // 对齐 iOS：无站点不报错，空搜索页仍展示豆瓣榜单（站点列表为空则不渲染）。
    setState(() {
      _sites = sites;
      final String initial = widget.initialSiteKey ?? '';
      _siteKey = sites.isEmpty
          ? null
          : sites
              .firstWhere(
                (SiteConfig s) => s.key == initial,
                orElse: () => sites.first,
              )
              .key;
    });
  }

  Future<void> _loadHistory() async {
    final Result<List<String>> result = await _history.recent();
    if (!mounted) return;
    final List<String> words = result.valueOrNull ?? const <String>[];
    setState(() => _historyWords = words);
  }

  /// 加载当前栏目的豆瓣榜单（对齐 iOS `SearchView.loadDoubanData`，L1812-L1829）：
  /// 已缓存且非强制 → 直接复用；单栏目失败静默（保持空列表，不阻断页面）。
  Future<void> _loadDouban({bool force = false}) async {
    final DoubanUseCases? uc = _douban;
    if (uc == null) return;
    final (String, String) tab = _doubanTabs[_doubanTab];
    final String tabName = tab.$1;
    if (!force && (_doubanCache[tabName]?.isNotEmpty ?? false)) return;
    setState(() => _doubanLoading = true);
    final Result<List<DoubanSubject>> result =
        await uc.collection(tab.$2, count: 20);
    if (!mounted) return;
    setState(() {
      _doubanLoading = false;
      _doubanCache[tabName] = result.valueOrNull ?? const <DoubanSubject>[];
    });
  }

  Future<void> _selectDoubanTab(int index) async {
    if (index == _doubanTab) return;
    setState(() => _doubanTab = index);
    await _loadDouban();
  }

  /// 打开豆瓣排行榜页（对齐 iOS `SearchView` → `DoubanRankingView`）。
  void _openRanking() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DoubanRankingPage()),
    );
  }

  Future<void> _submit(String raw) async {
    final String keyword = raw.trim();
    if (keyword.isEmpty) return;
    await _history.add(keyword);
    await _loadHistory();
    await _search(keyword);
  }

  /// 执行搜索（对齐 iOS `SearchView.performSearch` → `SpiderManager.searchStream`）。
  ///
  /// 关键对齐点（修复「点搜索没反应」）：
  ///   · **不依赖已选站点**：iOS 走 `searchStream` 对**全部源**并发搜索并逐批回调，
  ///     不要求先选中某个源；此处改为对 `_sites` 全部站点并发 `searchContent`，
  ///     并叠加附加源（占源 / 腾讯原生 / 兜底切片）。
  ///   · **立刻进入搜索结果态**：`_searched = true` + `_loading = true`，
  ///     顶栏出现「取消」、正文出现加载指示，**不再静默 return**；
  ///     无任何源时也会落到「没有找到相关影片」空态，用户始终有反馈。
  Future<void> _search(String keyword) async {
    final String kw = keyword.trim();
    if (kw.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _searched = true;
      _loading = true;
      _error = null;
      _results.clear();
    });

    final List<SiteConfig> sites = _sites ?? const <SiteConfig>[];
    final List<Future<void>> tasks = <Future<void>>[
      for (final SiteConfig s in sites) _searchSite(s.key, kw),
    ];
    _collectExtraSources(kw, tasks);
    await Future.wait(tasks);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// 单站点搜索（逐批并入；单源失败静默，不阻断其余源，对齐 iOS 逐源容错）。
  Future<void> _searchSite(String siteKey, String keyword) async {
    try {
      final Result<SearchContentResult> result =
          await _uc.searchContent(siteKey, keyword);
      final List<VodItem> items = result.valueOrNull?.list ?? const <VodItem>[];
      if (!mounted || items.isEmpty) return;
      setState(() {
        _mergeResults(
          items
              .map((VodItem v) => v.withEngineKey(siteKey))
              .toList(growable: false),
        );
      });
    } catch (_) {
      // 单源失败静默（对齐 iOS searchStream 的逐源 try/catch）。
    }
  }

  /// 附加结果源（S-设2 占源并列 / S-设3 腾讯原生 / Wave D 兜底切片）并入任务表。
  void _collectExtraSources(String keyword, List<Future<void>> tasks) {
    final ZhanyuanSearchUseCases? zhanyuan = _zhanyuan;
    final TencentVideoNativeSpider? tencent = _tencent;
    final SourceGovernanceUseCases? governance = _governance;

    if (zhanyuan != null) {
      tasks.add(
        zhanyuan
            .searchAll(
              keyword,
              onBatch: (List<VodItem> items) {
                if (!mounted || items.isEmpty) return;
                setState(() => _mergeResults(items));
              },
            )
            .catchError((Object _) {}),
      );
    }
    if (tencent != null) {
      tasks.add(
        tencent.search(keyword).then((List<VodItem> items) {
          if (!mounted || items.isEmpty) return;
          setState(() {
            _mergeResults(
              items
                  .map((VodItem v) =>
                      v.withEngineKey(TencentVideoNativeSpider.siteKey))
                  .toList(growable: false),
            );
          });
        }).catchError((Object _) {}),
      );
    }
    // Wave D · O-源1：兜底切片源（受 `fallback_enabled` 开关约束，内部自判）。
    if (governance != null) {
      tasks.add(
        governance
            .searchFallback(
              keyword,
              onBatch: (List<VodItem> items) {
                if (!mounted || items.isEmpty) return;
                setState(() => _mergeResults(items));
              },
            )
            .catchError((Object _) {}),
      );
    }
  }

  /// 去重并入结果（按 `engineKey|vodId|vodName`）。
  void _mergeResults(List<VodItem> items) {
    final Set<String> seen = _results
        .map((VodItem v) => '${v.engineKey ?? ''}|${v.vodId}|${v.vodName}')
        .toSet();
    for (final VodItem v in items) {
      if (seen.add('${v.engineKey ?? ''}|${v.vodId}|${v.vodName}')) {
        _results.add(v);
      }
    }
  }

  Future<void> _onSourceChanged(String key) async {
    if (key == _siteKey) return;
    setState(() => _siteKey = key);
    if (_searched) {
      await _search(_controller.text);
    }
  }

  Future<void> _clearHistory() async {
    await _history.clear();
    await _loadHistory();
  }

  Future<void> _useHistoryWord(String word) async {
    _controller.text = word;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    await _submit(word);
  }

  void _backToEmpty() {
    setState(() {
      _searched = false;
      _results.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 顶栏对齐 iOS `MainViews.swift SearchView`（L1360-L1414）：
      // 搜索框（放大镜 + 清除）→ 豆瓣排行榜入口（chart.bar.fill）→ 提交（arrow）。
      appBar: AppBar(
        titleSpacing: VboxSpacing.md,
        title: _buildSearchField(),
        actions: <Widget>[
          if (_searched)
            TextButton(
              onPressed: _backToEmpty,
              child: const Text('取消'),
            )
          else ...<Widget>[
            IconButton(
              tooltip: '豆瓣排行榜',
              icon: const Icon(Icons.bar_chart_rounded),
              onPressed: _openRanking,
            ),
            _buildSubmitButton(),
          ],
        ],
      ),
      body: _searched ? _buildResultState() : _buildEmptyState(),
    );
  }

  /// 顶栏搜索框（放大镜 + 输入 + 清除；对齐 iOS `SearchView` 搜索栏）。
  Widget _buildSearchField() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: VboxSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: VboxTypography.s16, color: scheme.outline),
          const SizedBox(width: VboxSpacing.sm),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: false,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '搜索影片、剧集',
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: _submit,
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (BuildContext context, TextEditingValue value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () {
                  _controller.clear();
                  _backToEmpty();
                },
                child: Icon(
                  Icons.close,
                  size: VboxTypography.s14,
                  color: scheme.outline,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 提交按钮（主色底 + 箭头；对齐 iOS `SearchView` 提交钮）。
  Widget _buildSubmitButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VboxSpacing.sm),
      child: SizedBox(
        width: 40,
        height: 36,
        child: FilledButton(
          onPressed: () => _submit(_controller.text),
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Icon(Icons.arrow_forward, size: 18),
        ),
      ),
    );
  }

  // ─────────────── 空态 ───────────────

  Widget _buildEmptyState() {
    final Failure? error = _error;
    if (error != null && _sites == null) {
      return _ErrorRetry(message: '$error', onRetry: _init);
    }
    final List<SiteConfig> sites = _sites ?? const <SiteConfig>[];
    final List<DoubanSubject> doubanItems =
        _doubanCache[_doubanTabs[_doubanTab].$1] ?? const <DoubanSubject>[];
    final bool showDouban = _douban != null;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.md),
      children: <Widget>[
        if (_historyWords.isNotEmpty) _buildHistory(),
        if (showDouban) ...<Widget>[
          _buildDoubanTabs(),
          _buildDoubanList(doubanItems),
          const Divider(height: VboxSpacing.xl),
        ],
        if (sites.isNotEmpty) _buildAllSites(sites),
        if (_historyWords.isEmpty && !showDouban && sites.isEmpty)
          const _EmptyHint(text: '输入关键词，搜索你想要的影片'),
      ],
    );
  }

  /// 豆瓣栏目标签行（对齐 iOS `SearchView.doubanTabs` 下划线标签）。
  Widget _buildDoubanTabs() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _doubanTabs.length; i++) ...<Widget>[
            if (i > 0) ...<Widget>[
              const SizedBox(width: VboxSpacing.md),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: scheme.outlineVariant,
                indent: 8,
                endIndent: 8,
              ),
              const SizedBox(width: VboxSpacing.md),
            ],
            GestureDetector(
              onTap: () => _selectDoubanTab(i),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _doubanTabs[i].$1,
                    style: TextStyle(
                      fontSize: VboxTypography.s14,
                      fontWeight: i == _doubanTab
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: i == _doubanTab
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2,
                    width: 24,
                    decoration: BoxDecoration(
                      color: i == _doubanTab
                          ? scheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(VboxRadii.r4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 豆瓣栏目数据列表（骨架屏 / 卡片行）。
  Widget _buildDoubanList(List<DoubanSubject> items) {
    if (_doubanLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: VboxSpacing.lg, vertical: VboxSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
      child: Column(
        children: <Widget>[
          for (final DoubanSubject subject in items) ...<Widget>[
            _DoubanCardRow(
              subject: subject,
              onTap: () => _runKeywordSearch(subject.title),
            ),
            const SizedBox(height: VboxSpacing.sm),
          ],
        ],
      ),
    );
  }

  /// 全部站点区块（对齐 iOS `SearchView`「全部站点 (N)」）。
  Widget _buildAllSites(List<SiteConfig> sites) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VboxSectionHeader(title: '全部站点 (${sites.length})'),
        for (final SiteConfig s in sites)
          _SourceTile(
            name: s.name.isEmpty ? s.key : s.name,
            selected: s.key == _siteKey,
            onTap: () => _onSourceChanged(s.key),
          ),
      ],
    );
  }

  /// 以关键词触发搜索（豆瓣卡片点击，对齐 iOS `runKeywordSearch`）。
  Future<void> _runKeywordSearch(String keyword) async {
    _controller.text = keyword;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    await _submit(keyword);
  }

  /// 搜索历史（时钟图标 + 标题 + 「清空」；对齐 iOS `SearchView` 历史区）。
  Widget _buildHistory() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
          child: Row(
            children: <Widget>[
              Icon(Icons.history, size: VboxTypography.s16, color: scheme.primary),
              const SizedBox(width: VboxSpacing.xs),
              Expanded(
                child: Text(
                  '搜索历史',
                  style: TextStyle(
                    fontSize: VboxTypography.s15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearHistory,
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
            itemCount: _historyWords.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: VboxSpacing.sm),
            itemBuilder: (BuildContext context, int index) {
              final String word = _historyWords[index];
              return VboxChip(
                label: word,
                dense: true,
                onTap: () => _useHistoryWord(word),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────── 结果态 ───────────────

  Widget _buildResultState() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Failure? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: () => _search(_controller.text));
    }
    if (_results.isEmpty) {
      return const _EmptyHint(text: '没有找到相关影片\n换个关键词试试');
    }

    final UiFormController formController = context.watch<UiFormController>();
    final UiForm form = formController.resolveAt(
      size: MediaQuery.sizeOf(context),
      orientation: MediaQuery.orientationOf(context),
    );

    if (form.isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(width: 180, child: _buildSourcePanel()),
          const VerticalDivider(width: 1),
          Expanded(child: _buildResultList()),
        ],
      );
    }

    return Column(
      children: <Widget>[
        _buildSourceChips(),
        const SizedBox(height: VboxSpacing.xs),
        Expanded(child: _buildResultList()),
      ],
    );
  }

  Widget _buildSourcePanel() {
    final List<SiteConfig> sites = _sites ?? const <SiteConfig>[];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.sm),
      children: <Widget>[
        for (final SiteConfig s in sites)
          _SourceTile(
            name: s.name.isEmpty ? s.key : s.name,
            selected: s.key == _siteKey,
            onTap: () => _onSourceChanged(s.key),
          ),
      ],
    );
  }

  Widget _buildSourceChips() {
    final List<SiteConfig> sites = _sites ?? const <SiteConfig>[];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
        itemCount: sites.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: VboxSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final SiteConfig s = sites[index];
          return VboxChip(
            label: s.name.isEmpty ? s.key : s.name,
            dense: true,
            selected: s.key == _siteKey,
            onTap: () => _onSourceChanged(s.key),
          );
        },
      ),
    );
  }

  Widget _buildResultList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.sm),
      itemCount: _results.length,
      itemBuilder: (BuildContext context, int index) {
        final VodItem vod = _results[index];
        return _ResultCard(vod: vod, onTap: () => _openDetail(vod));
      },
    );
  }

  void _openDetail(VodItem vod) {
    // 附加源结果（占源/腾讯）按 `engineKey` 路由详情；缺省用当前选中站点。
    final String? engineKey = vod.engineKey;
    final String key = (engineKey != null && engineKey.isNotEmpty)
        ? engineKey
        : (_siteKey ?? '');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DetailPage(
          siteKey: key,
          vodId: vod.vodId,
          title: vod.vodName,
        ),
      ),
    );
  }
}

/// 源列表项（横屏左栏）。
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.name,
    required this.selected,
    this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: VboxTypography.s13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? scheme.primary : scheme.onSurface,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// 豆瓣空搜索页卡片行（封面 + 标题 + 评分 + 副标题 + 「点击搜索」）。
///
/// 对齐 iOS `MainViews.swift SearchDoubanCardItem`（L2183-L2236）：封面 70×95、
/// 圆角 8；标题 15 semibold；黄色星形评分；副标题 12；底部主色「点击搜索 “标题”」；
/// 右侧放大镜图标。整卡点击 → 以条目标题触发搜索。
class _DoubanCardRow extends StatelessWidget {
  const _DoubanCardRow({required this.subject, this.onTap});

  final DoubanSubject subject;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String subtitle = subject.cardSubtitle?.isNotEmpty ?? false
        ? subject.cardSubtitle!
        : subject.genreText;

    return InkWell(
      onTap: onTap,
      borderRadius: VboxRadii.button,
      child: Container(
        padding: const EdgeInsets.all(VboxSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 70,
                height: 95,
                child: PlatformAsyncImage(url: subject.coverUrl, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: VboxSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    subject.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VboxTypography.s15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subject.hasRating) ...<Widget>[
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.star, size: 12, color: VboxColors.ratingStar),
                        const SizedBox(width: 4),
                        Text(
                          subject.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: VboxTypography.s13,
                            fontWeight: FontWeight.w700,
                            color: VboxColors.ratingStar,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: VboxTypography.s12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '点击搜索 “${subject.title}”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VboxTypography.s11,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: VboxSpacing.sm),
            Icon(
              Icons.search,
              size: 24,
              color: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果卡（缩略图 + 标题 + 备注）。
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.vod, this.onTap});

  final VodItem vod;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String subtitle = <String?>[
      if (vod.vodYear?.isNotEmpty ?? false) vod.vodYear,
      if (vod.vodRemarks?.isNotEmpty ?? false) vod.vodRemarks,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg, vertical: VboxSpacing.sm),
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