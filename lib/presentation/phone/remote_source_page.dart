/// phone 形态：远程源（远程默认源设置 + 订阅管理）。
///
/// 直连 [SubscriptionUseCases]（D21 轻量路线）；订阅源标签顶部为
/// 「远程默认源」设置区块——G-09 起与设置页订阅配置区块**共用**
/// [RemoteDefaultSourceSection]（对齐 iOS：设置页内联编辑 + 独立页同款区块），
/// 本页自身只承载订阅列表（添加 / 删除）与「源发现」标签。
/// G-01 phone 形态第二块（登记见 VBOX_PLAN 附录 C）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../core/utils/time_utils.dart';
import '../../domain/entities/library/library.dart';
import '../../domain/usecases/usecases.dart';
import '../widgets/settings/remote_default_source_section.dart';
import '../widgets/source_discovery_view.dart';

/// 远程源页面。
class RemoteSourcePage extends StatefulWidget {
  /// 构造。
  const RemoteSourcePage({super.key});

  @override
  State<RemoteSourcePage> createState() => _RemoteSourcePageState();
}

class _RemoteSourcePageState extends State<RemoteSourcePage>
    with SingleTickerProviderStateMixin {
  // 用例引用在 initState 缓存，避免跨 async gap 使用 context
  late final SubscriptionUseCases _subs;

  List<SubscriptionItem>? _items;
  Object? _error;
  bool _loaded = false;

  /// 顶部标签（订阅源 / 源发现）控制器。
  late final TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _subs = context.read<SubscriptionUseCases>();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadSubs();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final int index = _tabController.index;
    if (index != _tabIndex) {
      setState(() => _tabIndex = index);
    }
  }

  Future<void> _loadSubs() async {
    final Result<List<SubscriptionItem>> result = await _subs.list();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _error = result.failureOrNull;
      _items = result.valueOrNull ?? const <SubscriptionItem>[];
    });
  }

  /// 弹出添加订阅对话框。
  Future<void> _add() async {
    final SubscriptionItem? created = await showDialog<SubscriptionItem>(
      context: context,
      builder: (BuildContext context) => const _AddSubscriptionDialog(),
    );
    if (created == null || !mounted) return;
    final Result<int> result = await _subs.add(created);
    if (!mounted) return;
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败：$failure')),
      );
      return;
    }
    await _loadSubs();
  }

  Future<void> _remove(SubscriptionItem item) async {
    final int? id = item.id;
    if (id == null) return;
    await _subs.remove(id);
    await _loadSubs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程源'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[Tab(text: '订阅源'), Tab(text: '源发现')],
        ),
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('订阅'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _buildSubscriptionsTab(),
          const SourceDiscoveryView(),
        ],
      ),
    );
  }

  /// 订阅源标签：远程默认源设置区块（与设置页共用）+ 订阅列表。
  Widget _buildSubscriptionsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: RemoteDefaultSourceSection(),
        ),
        const Divider(height: 1),
        Expanded(child: _buildSubscriptions()),
      ],
    );
  }

  Widget _buildSubscriptions() {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final Object? error = _error;
    if (error != null) {
      return _ErrorRetry(message: '$error', onRetry: _loadSubs);
    }
    final List<SubscriptionItem> items = _items ?? const <SubscriptionItem>[];
    if (items.isEmpty) {
      return const _EmptyHint(text: '暂无订阅\n点击右下角「订阅」添加远程源地址');
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final SubscriptionItem item = items[index];
        final String synced = item.neverSynced
            ? '从未同步'
            : '上次同步 ${TimeUtils.relative(TimeUtils.fromUnixSeconds(item.lastSyncAt))}';
        return ListTile(
          leading: const Icon(Icons.rss_feed),
          title: Text(item.dyname, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${item.dyurl}\n$synced',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '移除',
            onPressed: () => _remove(item),
          ),
          onTap: () {
            // 拉取订阅内容待 Spider 引擎接线（G-03）
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('「${item.dyname}」内容拉取待 Spider 引擎接线')),
            );
          },
        );
      },
    );
  }
}

/// 添加订阅对话框。
class _AddSubscriptionDialog extends StatefulWidget {
  const _AddSubscriptionDialog();

  @override
  State<_AddSubscriptionDialog> createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<_AddSubscriptionDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _name.text.trim();
    final String url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    Navigator.of(context).pop(
      SubscriptionItem(dyname: name, dyurl: url, lastSyncAt: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加订阅'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '订阅名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: '订阅地址'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
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
