/// 全端共享视图：收藏列表 / 历史列表（直连 UseCase）。
///
/// 单一页树（`shell/HomeShellPage` 的 `ShelfView`）在竖/横双排布下共用同一套
/// 列表逻辑与展示。状态接入直连领域层 UseCase（D21 轻量路线）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/result.dart';
import '../../core/utils/time_utils.dart';
import '../../domain/entities/library/library.dart';
import '../../domain/usecases/usecases.dart';
import '../welfare/welfare_replay_bridge.dart';
import 'detail_page.dart';

/// 收藏 Tab（直连 [FavoriteUseCases]）。
class FavoritesView extends StatefulWidget {
  /// 构造。
  const FavoritesView({super.key});

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  // 用例引用在 initState 缓存，避免跨 async gap 使用 context
  late final FavoriteUseCases _uc;
  List<FavoriteItem>? _items;
  Object? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _uc = context.read<FavoriteUseCases>();
    _load();
  }

  Future<void> _load() async {
    final Result<List<FavoriteItem>> result = await _uc.list();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _error = result.failureOrNull;
      _items = result.valueOrNull ?? const <FavoriteItem>[];
    });
  }

  Future<void> _remove(FavoriteItem item) async {
    final int? id = item.id;
    if (id == null) return;
    await _uc.remove(id);
    await _load();
  }

  Future<void> _clearAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清空收藏'),
        content: const Text('确定清空全部收藏？此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _uc.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final Object? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _load);
    }
    final List<FavoriteItem> items = _items ?? const <FavoriteItem>[];
    if (items.isEmpty) {
      return const _EmptyHint(text: '暂无收藏\n去远程源订阅你喜欢的资源吧');
    }
    return ListView.separated(
      itemCount: items.length + 1,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('清空'),
            ),
          );
        }
        final FavoriteItem item = items[index - 1];
        return ListTile(
          leading: const Icon(Icons.movie_outlined),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${item.laiyuan.isEmpty ? '未知来源' : item.laiyuan}'
            ' · ${TimeUtils.relative(TimeUtils.fromUnixSeconds(item.addedAt))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '移除',
            onPressed: () => _remove(item),
          ),
          onTap: () {
            // W-福2：福利记录分流到「福利重播桥」（laiyuan 前缀 [福利]
            // + detailua=platformKey）；其余走详情页·播放入口接线
            // （laiyuan=站点 key，detailurl=影片 ID，jishu=剧集索引）。
            if (isWelfareReplayRecord(
              laiyuan: item.laiyuan,
              detailua: item.detailua,
            )) {
              unawaited(_openWelfare(item));
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => DetailPage(
                  siteKey: item.laiyuan,
                  vodId: item.detailurl,
                  initialIndex: item.jishu,
                  title: item.name,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 打开福利重播桥（对齐 iOS `WelfareBridgeContainer`）。
  Future<void> _openWelfare(FavoriteItem item) => openWelfareReplayBridge(
        context,
        platformKey: item.detailua,
        vodId: item.detailurl,
        vodName: item.name,
        vodPic: item.imgurl,
      );
}

/// 历史 Tab（直连 [HistoryUseCases]）。
class HistoryView extends StatefulWidget {
  /// 构造。
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  // 用例引用在 initState 缓存，避免跨 async gap 使用 context
  late final HistoryUseCases _uc;
  List<HistoryItem>? _items;
  Object? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _uc = context.read<HistoryUseCases>();
    _load();
  }

  Future<void> _load() async {
    final Result<List<HistoryItem>> result =
        await _uc.recent(limit: HistoryUseCases.defaultLimit);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _error = result.failureOrNull;
      _items = result.valueOrNull ?? const <HistoryItem>[];
    });
  }

  Future<void> _remove(HistoryItem item) async {
    final int? id = item.id;
    if (id == null) return;
    await _uc.remove(id);
    await _load();
  }

  Future<void> _clearAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定清空全部播放历史？此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _uc.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final Object? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _load);
    }
    final List<HistoryItem> items = _items ?? const <HistoryItem>[];
    if (items.isEmpty) {
      return const _EmptyHint(text: '暂无播放历史\n看完的片子会出现在这里');
    }
    return ListView.separated(
      itemCount: items.length + 1,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('清空'),
            ),
          );
        }
        final HistoryItem item = items[index - 1];
        final int percent = (item.clampedProgress * 100).round();
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: item.clampedProgress,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '第 ${item.jishu} 集 · $percent%'
                ' · ${TimeUtils.relative(TimeUtils.fromUnixSeconds(item.lastPlayedAt))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '移除',
            onPressed: () => _remove(item),
          ),
          onTap: () {
            // W-福2：福利记录分流到「福利重播桥」；其余续播入口接线
            // （进入详情页并定位到历史剧集）。
            if (isWelfareReplayRecord(
              laiyuan: item.laiyuan,
              detailua: item.detailua,
            )) {
              unawaited(_openWelfare(item));
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => DetailPage(
                  siteKey: item.laiyuan,
                  vodId: item.detailurl,
                  initialIndex: item.jishu,
                  title: item.name,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 打开福利重播桥（对齐 iOS `WelfareBridgeContainer`）。
  Future<void> _openWelfare(HistoryItem item) => openWelfareReplayBridge(
        context,
        platformKey: item.detailua,
        vodId: item.detailurl,
        vodName: item.name,
        vodPic: item.imgurl,
      );
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
