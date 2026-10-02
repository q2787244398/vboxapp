/// 直播播放接入 Sheet（批次 E · E-02）。
///
/// 对齐 iOS `LivePlayerSheet`：点击频道卡弹出，自动解析线路并连接首线路
/// （`resolveAllSources` = 直接取 [LiveChannel.sources]）。顶部 16:9 预览区
/// （视频画面由平台侧播放器渲染，Flutter 侧经 [PlayerController] 驱动，
/// 此处仅展示连接状态占位）+ 线路列表切换。
///
/// [onPlayRoute] 供测试注入，避免单测触碰真实方法通道；缺省走
/// [PlayerController.instance]（live 路由）。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/live/live.dart';
import '../../../domain/entities/player/player.dart';
import '../../../platform/player/player_controller.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';

/// 直播线路播放回调（url → 打开并播放）。
typedef LiveRoutePlayHandler = Future<void> Function(String url);

/// 截断长 URL 显示（中段省略）。
String _truncateUrl(String url) {
  if (url.length <= 48) return url;
  return '${url.substring(0, 24)}...${url.substring(url.length - 20)}';
}

/// 直播播放 Sheet（线路解析 + 连接 + 线路切换）。
class LivePlayerSheet extends StatefulWidget {
  /// 构造。
  const LivePlayerSheet({super.key, required this.channel, this.onPlayRoute});

  /// 待播放频道。
  final LiveChannel channel;

  /// 播放回调（null → [PlayerController.instance]）。
  final LiveRoutePlayHandler? onPlayRoute;

  @override
  State<LivePlayerSheet> createState() => _LivePlayerSheetState();
}

class _LivePlayerSheetState extends State<LivePlayerSheet> {
  late final List<String> _routes;
  int _current = 0;
  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _routes = _resolveRoutes();
    _autoPlay();
  }

  List<String> _resolveRoutes() {
    final List<String> sources = widget.channel.sources;
    if (sources.isNotEmpty) return List<String>.of(sources);
    final String playURL = widget.channel.playURL;
    if (playURL.isNotEmpty) return <String>[playURL];
    return <String>[];
  }

  Future<void> _autoPlay() {
    if (_routes.isEmpty) {
      setState(() {
        _connecting = false;
        _error = '暂无可用线路';
      });
      return Future<void>.value();
    }
    return _play(_current);
  }

  Future<void> _play(int index) async {
    if (index < 0 || index >= _routes.length) return;
    setState(() {
      _current = index;
      _connecting = true;
      _error = null;
    });
    try {
      final LiveRoutePlayHandler handler = widget.onPlayRoute ?? _defaultPlay;
      await handler(_routes[index]);
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '连接失败：$e';
        });
      }
    }
  }

  Future<void> _defaultPlay(String url) async {
    final PlayerController controller = PlayerController.instance;
    await controller.open(
      PlayerSource(url: url, title: widget.channel.name, isLive: true),
    );
    await controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _titleRow(scheme),
            Flexible(flex: 9, child: _preview()),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VboxSpacing.lg, VboxSpacing.md, VboxSpacing.lg, VboxSpacing.xs),
              child: Text(
                '共 ${_routes.length} 条线路',
                style: TextStyle(
                  fontSize: VboxTypography.s13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(flex: 11, child: _routeList(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _titleRow(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VboxSpacing.lg, VboxSpacing.sm, VboxSpacing.sm, VboxSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              widget.channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: VboxTypography.s18,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: _previewBody()),
    );
  }

  Widget _previewBody() {
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 40, color: Colors.orange),
          const SizedBox(height: VboxSpacing.sm),
          Padding(
            padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => _play(_current),
            child: const Text('重试', style: TextStyle(color: Colors.orange)),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_connecting) ...<Widget>[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                color: Colors.white70, strokeWidth: 2.5),
          ),
          const SizedBox(height: VboxSpacing.sm),
          const Text('正在连接直播流…',
              style: TextStyle(fontSize: 13, color: Colors.white70)),
        ] else ...<Widget>[
          const Icon(Icons.play_circle_outline, size: 48, color: Colors.white54),
          const SizedBox(height: VboxSpacing.sm),
          const Text('线路已就绪',
              style: TextStyle(fontSize: 13, color: Colors.white70)),
        ],
      ],
    );
  }

  Widget _routeList(ColorScheme scheme) {
    if (_routes.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      padding: VboxSpacing.symmetric(
          horizontal: VboxSpacing.lg, vertical: VboxSpacing.sm),
      itemCount: _routes.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: VboxSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        final bool active = index == _current;
        return _RouteItem(
          index: index,
          url: _routes[index],
          active: active,
          scheme: scheme,
          onTap: () => _play(index),
        );
      },
    );
  }
}

/// 单条线路项（对齐 iOS：编号圆 + 线路名/截断 URL + 播放指示）。
class _RouteItem extends StatelessWidget {
  const _RouteItem({
    required this.index,
    required this.url,
    required this.active,
    required this.scheme,
    required this.onTap,
  });

  final int index;
  final String url;
  final bool active;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = scheme.primary;
    return Material(
      color: active ? accent.withValues(alpha: 0.08) : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VboxRadii.r12),
        side: BorderSide(
          color: active ? accent.withValues(alpha: 0.3) : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(VboxSpacing.sm),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 16,
                backgroundColor: active ? accent : scheme.surfaceContainerHighest,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: VboxTypography.s14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: VboxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '线路 ${index + 1}',
                      style: TextStyle(
                        fontSize: VboxTypography.s15,
                        fontWeight: FontWeight.w500,
                        color: active ? accent : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _truncateUrl(url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: VboxTypography.s11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                active ? Icons.play_circle_fill : Icons.play_circle,
                size: 24,
                color: active ? accent : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}