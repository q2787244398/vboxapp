import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/config_service.dart';
import '../services/node_service.dart';

/// Configuration center page: engine status, spider settings, pan (cloud
/// storage) credentials, import/export.
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  Future<List<VodSite>>? _sitesFuture;
  String? _selectedSiteKey;

  @override
  void initState() {
    super.initState();
    _sitesFuture = context
        .read<NodeService>()
        .getSites()
        .then((sites) => sites)
        .catchError((_) => <VodSite>[VodSite(key: '', name: '', api: '')]);
  }

  Future<void> _restartEngine() async {
    final node = context.read<NodeService>();
    final config = context.read<ConfigService>();
    final port = await node.startNode(config.spiderBundle);
    if (port == null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('启动失败，请检查 bundle 路径')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConfigService, NodeService>(
      builder: (context, config, node, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('配置'),
            actions: [
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: '启动/重启引擎',
                onPressed: _restartEngine,
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => context.go('/node'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _engineStatusCard(node),

              const SizedBox(height: 16),

              _section('网盘登录', [
                ListTile(
                  leading: const Icon(Icons.login, color: Color(0xFF58A6FF)),
                  title: const Text('管理网盘账号',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('14 个网盘 Provider · 扫码/短信/密码',
                      style: TextStyle(fontSize: 12, color: Colors.white54)),
                  onTap: () => context.go('/login'),
                ),
              ]),

              const SizedBox(height: 16),

              _section('API', [
                _textField(
                  context,
                  config,
                  label: 'API 地址',
                  initial: config.apiHost,
                  onChanged: (v) => config.setValue('apiHost', v),
                ),
                _textField(
                  context,
                  config,
                  label: 'Spider Bundle',
                  initial: config.spiderBundle,
                  onChanged: (v) => config.setValue('spiderBundle', v),
                ),
              ]),

              const SizedBox(height: 16),

              _section('播放器', [
                _switch(context, config, 'autoPlay', '自动播放'),
                _switch(context, config, 'showCover', '显示封面'),
                _textField(
                  context,
                  config,
                  label: '缓冲时间 (ms)',
                  initial: '${config.bufferMs}',
                  onChanged: (v) => config.setValue('bufferMs', int.tryParse(v) ?? 2000),
                ),
              ]),

              const SizedBox(height: 16),

              _section('网络', [
                _switch(context, config, 'enableProxy', '启用代理'),
                if (config.enableProxy)
                  _textField(
                    context,
                    config,
                    label: '代理地址',
                    initial: config.proxyUrl,
                    onChanged: (v) => config.setValue('proxyUrl', v),
                  ),
              ]),

              const SizedBox(height: 16),

              _section('云盘', [
                _textField(
                  context,
                  config,
                  label: 'Aliyun Token',
                  initial: config.getValue('aliToken', '')!,
                  onChanged: (v) => config.setValue('aliToken', v),
                ),
                _textField(
                  context,
                  config,
                  label: 'Baidu Cookie',
                  initial: config.getValue('baiduCookie', '')!,
                  onChanged: (v) => config.setValue('baiduCookie', v),
                ),
                _textField(
                  context,
                  config,
                  label: 'Quark Cookie',
                  initial: config.getValue('quarkCookie', '')!,
                  onChanged: (v) => config.setValue('quarkCookie', v),
                ),
              ]),

              const SizedBox(height: 16),

              _section('站点', [
                FutureBuilder<List<VodSite>>(
                  future: _sitesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final sites = snapshot.data ?? [];
                    if (sites.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无可用站点',
                            style: TextStyle(color: Colors.white54)),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sites.map((site) {
                        final isSelected = _selectedSiteKey == site.key;
                        return ChoiceChip(
                          label: Text(site.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _selectedSiteKey = selected ? site.key : null);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 16),

              _section('导入/导出', [
                ListTile(
                  leading: const Icon(Icons.upload),
                  title: const Text('导出配置'),
                  onTap: () async {
                    final json = await config.exportConfig();
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('配置已导出 (${json.length} 字符)')));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('导入配置 (JSON)'),
                  onTap: () async {
                    final ctrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('导入配置'),
                        content: TextField(
                          controller: ctrl,
                          maxLines: 6,
                          decoration: const InputDecoration(
                              hintText: '粘贴导出的 JSON 配置'),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('确定')),
                        ],
                      ),
                    );
                    if (ok == true && ctrl.text.isNotEmpty &&
                        mounted) {
                      final success = await config.importConfig(ctrl.text);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(success ? '导入成功' : '导入失败')));
                    }
                  },
                ),
              ]),

              const SizedBox(height: 16),

              _section('重置', [
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
                  title: const Text('重置所有设置',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('确认重置'),
                        content: const Text('确定要重置所有设置吗？此操作不可撤销。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('确认',
                                  style: TextStyle(color: Colors.redAccent))),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await config.reset();
                    }
                  },
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _engineStatusCard(NodeService node) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: node.isRunning ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.isRunning
                        ? 'Node.js 引擎运行中 (端口 ${node.port})'
                        : 'Node.js 引擎未运行',
                  ),
                ),
              ],
            ),
            if (node.isRunning) ...[
              const SizedBox(height: 8),
              Text('Dart 通信端口: ${node.dartPort}',
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
            if (node.error != null)
              Text('最近错误: ${node.error}',
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70)),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }

  Widget _switch(
      BuildContext context, ConfigService config, String key, String label) {
    return SwitchListTile(
      title: Text(label),
      value: config.getValue(key, false)!,
      onChanged: (v) => config.setValue(key, v),
    );
  }

  Widget _textField(
    BuildContext context,
    ConfigService config, {
    required String label,
    required String initial,
    required ValueChanged<String> onChanged,
  }) {
    final ctrl = TextEditingController(text: initial);
    return ListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 220,
        child: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '—',
          ),
          style: const TextStyle(fontSize: 13, color: Colors.white70),
          onSubmitted: onChanged,
        ),
      ),
    );
  }
}
