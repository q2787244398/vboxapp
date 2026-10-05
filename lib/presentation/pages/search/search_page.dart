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
import '../../../domain/entities/spider/spider.dart';
import '../../../domain/usecases/usecases.dart';
import '../../../platform/spider/spider.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/detail_page.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';

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
  static const int _rankCount = 10;

  late final ContentBrowseUseCases _uc;
  late final SearchHistoryUseCases _history;

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
  List<VodItem> _ranks = const <VodItem>[];

  bool _loading = false;
  Failure? _error;
  bool _searched = false;
  final List<VodItem> _results = <VodItem>[];

  @override
  void initState() {
    super.initState();
    _uc = context.read<ContentBrowseUseCases>();
    _history = context.read<SearchHistoryUseCases>();
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
    final Result<List<SiteConfig>> result = await _uc.listSites();
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    final List<SiteConfig> sites = result.valueOrNull ?? const <SiteConfig>[];
    if (sites.isEmpty) {
      setState(() => _error = const UnknownFailure('无可用站点'));
      return;
    }
    _sites = sites;
    final String initial = widget.initialSiteKey ?? '';
    final SiteConfig target = sites.firstWhere(
      (SiteConfig s) => s.key == initial,
      orElse: () => sites.first,
    );
    _siteKey = target.key;
    await _loadRanks(target.key);
  }

  Future<void> _loadHistory() async {
    final Result<List<String>> result = await _history.recent();
    if (!mounted) return;
    final List<String> words = result.valueOrNull ?? const <String>[];
    setState(() => _historyWords = words);
  }

  Future<void> _loadRanks(String siteKey) async {
    final Result<HomeContentResult> result = await _uc.homeContent(siteKey);
    if (!mounted) return;
    final List<VodItem> list = result.valueOrNull?.list ?? const <VodItem>[];
    setState(() {
      _ranks = list.take(_rankCount).toList(growable: false);
    });
  }

  Future<void> _submit(String raw) async {
    final String keyword = raw.trim();
    if (keyword.isEmpty) return;
    await _history.add(keyword);
    await _loadHistory();
    await _search(keyword);
  }

  Future<void> _search(String keyword) async {
    final String? siteKey = _siteKey;
    if (siteKey == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final Result<SearchContentResult> result =
        await _uc.searchContent(siteKey, keyword);
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    setState(() {
      _loading = false;
      if (failure != null) {
        _error = failure;
        return;
      }
      _results
        ..clear()
        ..addAll(result.valueOrNull?.list ?? const <VodItem>[]);
      _searched = true;
    });
    // S-设2/S-设3：附加结果源（占源并列 + 腾讯视频原生）并行并入，
    // 对齐 iOS `SpiderManager.search` 的多源合并语义。
    await _searchExtraSources(keyword);
  }

  /// 附加结果源搜索（逐批并入结果，不覆盖主源结果）。
  Future<void> _searchExtraSources(String keyword) async {
    final ZhanyuanSearchUseCases? zhanyuan = _zhanyuan;
    final TencentVideoNativeSpider? tencent = _tencent;
    final SourceGovernanceUseCases? governance = _governance;
    if (zhanyuan == null && tencent == null && governance == null) return;

    final List<Future<void>> tasks = <Future<void>>[];
    if (zhanyuan != null) {
      tasks.add(
        zhanyuan
            .searchAll(
              keyword,
              onBatch: (List<VodItem> items) {
                if (!mounted || items.isEmpty) return;
                setState(() {
                  _mergeResults(items);
                  _searched = true;
                  _error = null;
                });
              },
            )
            .catchError((Object _) {}),
      );
    }
    if (tencent != null) {
      tasks.add(
        tencent.search(keyword).then((List<VodItem> items) {
          if (!mounted || items.isEmpty) return;
          final List<VodItem> stamped = items
              .map((VodItem v) =>
                  v.withEngineKey(TencentVideoNativeSpider.siteKey))
              .toList(growable: false);
          setState(() {
            _mergeResults(stamped);
            _searched = true;
            _error = null;
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
                setState(() {
                  _mergeResults(items);
                  _searched = true;
                  _error = null;
                });
              },
            )
            .catchError((Object _) {}),
      );
    }
    await Future.wait(tasks);
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
    } else {
      await _loadRanks(key);
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
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: false,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索影片 / 剧集',
            border: InputBorder.none,
          ),
          onSubmitted: _submit,
        ),
        actions: <Widget>[
          if (_searched)
            TextButton(
              onPressed: _backToEmpty,
              child: const Text('取消'),
            )
          else
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => _submit(_controller.text),
            ),
        ],
      ),
      body: _searched ? _buildResultState() : _buildEmptyState(),
    );
  }

  // ─────────────── 空态 ───────────────

  Widget _buildEmptyState() {
    final Failure? error = _error;
    if (error != null && _sites == null) {
      return _ErrorRetry(message: '$error', onRetry: _init);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.md),
      children: <Widget>[
        if (_historyWords.isNotEmpty) _buildHistory(),
        if (_ranks.isNotEmpty) _buildRanks(),
        if (_historyWords.isEmpty && _ranks.isEmpty) const _EmptyHint(text: '输入关键词，搜索你想要的影片'),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
          child: Row(
            children: <Widget>[
              const Expanded(child: VboxSectionHeader(title: '搜索历史')),
              IconButton(
                tooltip: '清空历史',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: _clearHistory,
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

  Widget _buildRanks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const VboxSectionHeader(title: '榜单'),
        for (int i = 0; i < _ranks.length; i++)
          _RankRow(
            index: i,
            vod: _ranks[i],
            onTap: () => _openDetail(_ranks[i]),
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

/// 榜单行（名次 + 缩略图 + 标题 + 备注）。
class _RankRow extends StatelessWidget {
  const _RankRow({required this.index, required this.vod, this.onTap});

  final int index;
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
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: VboxTypography.s16,
                  fontWeight: FontWeight.w700,
                  color: index < 3 ? scheme.primary : scheme.outline,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: VboxRadii.button,
              child: SizedBox(
                width: 52,
                height: 72,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VboxTypography.s14,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
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