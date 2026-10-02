/// 直播页（批次 E · E-01）。
///
/// 对齐 iOS `LiveTVView`：顶部**频道源胶囊**（当前源 + 切换源浮层）、
/// **分类胶囊**（横向滚动，按 `cat_N` 取循环调色板）、**双列频道卡**
/// （16:9 台标封面 + 频道名 + 线路数）。数据由 [LiveTvController] 提供
/// （源持久化 + 订阅源拉取/解析 + 动态分类 + 分组合并多线路）。
///
/// 契约键：`live_tv_current_source`（LiveTvController 内部读写）。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/live/live.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import 'live_tv_controller.dart';

/// 直播页（频道源胶囊 + 分类胶囊 + 双列频道卡）。
class LiveTVPage extends StatefulWidget {
  /// 构造（[controller] 供测试注入；缺省自建并自管生命周期）。
  const LiveTVPage({super.key, this.controller});

  /// 外部注入的控制器（null → 页面自建）。
  final LiveTvController? controller;

  @override
  State<LiveTVPage> createState() => _LiveTVPageState();
}

class _LiveTVPageState extends State<LiveTVPage> {
  late final LiveTvController _controller;
  late final bool _ownsController;

  /// 当前选中分类（tid）与首帧加载中标记。
  String? _selectedTid;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? LiveTvController();
    _bootstrap();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_ownsController) await _controller.init();
    await _controller.ensureLoaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _retry() async {
    final String? url = _controller.currentSource.sourceURL;
    if (url == null) return;
    if (mounted) setState(() => _loading = true);
    await _controller.fetchSubscribeChannels(url);
    if (mounted) setState(() => _loading = false);
  }

  LiveCategory? _activeCategory(List<LiveCategory> categories) {
    if (categories.isEmpty) return null;
    for (final LiveCategory c in categories) {
      if (c.tid == _selectedTid) return c;
    }
    return categories.first;
  }

  Future<void> _selectSource(LiveSourceType source) async {
    if (source.id == _controller.currentSource.id) return;
    setState(() => _selectedTid = null);
    await _controller.switchSource(source);
  }

  Future<void> _showSourceSheet() async {
    final LiveSourceType? picked = await showModalBottomSheet<LiveSourceType>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => _SourceSheet(
        sources: _controller.availableSources,
        currentId: _controller.currentSource.id,
      ),
    );
    if (picked != null) await _selectSource(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('直播')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildSourceCapsule(),
              if (_buildCategories() != null) _buildCategories()!,
              Expanded(child: _buildBody()),
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────── 频道源胶囊 ────────────────────────────

  Widget _buildSourceCapsule() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final LiveSourceType source = _controller.currentSource;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VboxSpacing.lg, VboxSpacing.sm, VboxSpacing.lg, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: VboxRadii.chip,
          onTap: _showSourceSheet,
          child: Container(
            padding: VboxSpacing.symmetric(
                horizontal: VboxSpacing.md, vertical: VboxSpacing.sm),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: VboxRadii.chip,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.settings_input_antenna,
                    size: VboxTypography.s14, color: scheme.primary),
                const SizedBox(width: VboxSpacing.xs),
                Text(
                  source.displayName,
                  style: TextStyle(
                    fontSize: VboxTypography.s13,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: VboxSpacing.xs),
                Icon(Icons.expand_more,
                    size: VboxTypography.s14, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────── 分类胶囊 ────────────────────────────

  Widget? _buildCategories() {
    final List<LiveCategory> categories = _controller.categories;
    if (categories.isEmpty) return null;
    final LiveCategory active = _activeCategory(categories)!;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: VboxSpacing.symmetric(
            horizontal: VboxSpacing.lg, vertical: VboxSpacing.sm),
        itemCount: categories.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: VboxSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          final LiveCategory c = categories[index];
          return _CategoryCapsule(
            category: c,
            selected: c.tid == active.tid,
            onTap: () => setState(() => _selectedTid = c.tid),
          );
        },
      ),
    );
  }

  // ──────────────────────────── 双列频道卡 ────────────────────────────

  Widget _buildBody() {
    if (_loading && _controller.categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? error = _controller.lastError;
    if (error != null && _controller.categories.isEmpty) {
      return _ErrorRetry(message: error, onRetry: _retry);
    }
    final List<LiveCategory> categories = _controller.categories;
    if (categories.isEmpty) {
      return const _EmptyHint(text: '暂无频道\n点击上方切换直播源');
    }
    final LiveCategory active = _activeCategory(categories)!;
    final List<LiveChannel> channels =
        _controller.channelsForGroup(active.tid);
    if (channels.isEmpty) {
      return const _EmptyHint(text: '该分类暂无频道');
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
          VboxSpacing.lg, VboxSpacing.sm, VboxSpacing.lg, VboxSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: VboxSpacing.md,
        crossAxisSpacing: VboxSpacing.md,
        childAspectRatio: 16 / 11,
      ),
      itemCount: channels.length,
      itemBuilder: (BuildContext context, int index) =>
          _ChannelCard(channel: channels[index]),
    );
  }
}

/// 分类胶囊（对齐 iOS `CategoryTabButton`：未选中 tint@10% 底 + tint 字，
/// 选中 tint 填充 + 白字；图标优先台标，缺省 tv 图标）。
class _CategoryCapsule extends StatelessWidget {
  const _CategoryCapsule({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final LiveCategory category;
  final bool selected;
  final VoidCallback onTap;

  static Color _tint(LiveCategory c) => VboxColors
      .liveCategoryPalette[c.paletteIndex % VboxColors.liveCategoryPalette.length];

  @override
  Widget build(BuildContext context) {
    final Color tint = _tint(category);
    final Color foreground = selected ? Colors.white : tint;
    final Color background =
        selected ? tint : tint.withValues(alpha: 0.10);

    return Material(
      color: background,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: VboxSpacing.symmetric(
              horizontal: VboxSpacing.lg, vertical: VboxSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (category.logo != null && category.logo!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: VboxSpacing.xs),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: PlatformAsyncImage(
                      url: category.logo,
                      fit: BoxFit.contain,
                      placeholderColor: Colors.transparent,
                      placeholder: Icon(Icons.live_tv,
                          size: VboxTypography.s14, color: foreground),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: VboxSpacing.xs),
                  child: Icon(Icons.live_tv,
                      size: VboxTypography.s14, color: foreground),
                ),
              Text(
                category.name,
                style: TextStyle(
                  fontSize: VboxTypography.s15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 频道卡（对齐 iOS `ChannelGridItem`：16:9 台标封面 + 线路数 + 频道名）。
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel});

  final LiveChannel channel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return VboxCard(
      padding: EdgeInsets.zero,
      radius: VboxRadii.r12,
      child: Column(
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(VboxRadii.r12 - 1),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: scheme.surfaceContainerHighest,
                child: PlatformAsyncImage(
                  url: channel.logo,
                  fit: BoxFit.contain,
                  placeholderColor: scheme.surfaceContainerHighest,
                  placeholder: Center(
                    child: Icon(
                      Icons.live_tv,
                      size: VboxTypography.s24,
                      color: Colors.orange.withValues(alpha: 0.60),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: VboxSpacing.sm, vertical: VboxSpacing.xs + 2),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 56,
                  child: Text(
                    '${channel.routeCount}条线路',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VboxTypography.s11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: VboxTypography.s14,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 56),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 切换源浮层（列出全部可用源，选中项勾选）。
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.sources, required this.currentId});

  final List<LiveSourceType> sources;
  final String currentId;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '选择直播源 ${sources.length}',
                style: TextStyle(
                  fontSize: VboxTypography.s18,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sources.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final LiveSourceType source = sources[index];
                  final bool selected = source.id == currentId;
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.settings_input_antenna,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(
                      source.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle, color: scheme.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(source),
                  );
                },
              ),
            ),
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