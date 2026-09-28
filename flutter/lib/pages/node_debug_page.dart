import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/node_service.dart';

/// Node.js spider engine debug/management page.
class NodeDebugPage extends StatefulWidget {
  const NodeDebugPage({super.key});

  @override
  State<NodeDebugPage> createState() => _NodeDebugPageState();
}

class _NodeDebugPageState extends State<NodeDebugPage> {
  final TextEditingController _bundleCtrl =
      TextEditingController(text: 'spider.js');

  @override
  void dispose() {
    _bundleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NodeService>(
      builder: (context, node, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Node.js 引擎'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Status card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: node.isRunning
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            node.isRunning ? 'Node.js 运行中' : 'Node.js 未运行',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          if (node.isRunning)
                            Text('端口: ${node.port}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                      if (node.isRunning) ...[
                        const SizedBox(height: 8),
                        Text('Dart 通信端口: ${node.dartPort}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white54)),
                        if (node.lastStarted != null)
                          Text(
                              '启动于 ${node.lastStarted?.toLocal()}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white54)),
                      ],
                      if (node.error != null)
                        const SizedBox(
                            height: 8),
                      if (node.error != null)
                        Text('最近错误: ${node.error}',
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Bundle input
              TextField(
                controller: _bundleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Spider Bundle 路径',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              // Controls
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: node.isRunning
                          ? null
                          : () async {
                              final port =
                                  await node.startNode(_bundleCtrl.text.trim());
                              if (port == null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('启动失败')));
                              }
                            },
                      child: const Text('启动'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: node.isRunning
                          ? node.stopNode
                          : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white),
                      child: const Text('停止'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: node.isRunning
                          ? () => node
                              .restartNode(_bundleCtrl.text.trim())
                          : null,
                      child: const Text('重启'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              const Text('API 测试',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('站点列表'),
                    onPressed: node.isRunning
                        ? () => _testApi(node, '/api/sites', context)
                        : null,
                  ),
                  ActionChip(
                    label: const Text('健康检查'),
                    onPressed: node.isRunning
                        ? () => _testApi(node, '/api/health', context)
                        : null,
                  ),
                  ActionChip(
                    label: const Text('直播源'),
                    onPressed: node.isRunning
                        ? () => _testApi(node, '/api/live', context)
                        : null,
                  ),
                  ActionChip(
                    label: const Text('当前配置'),
                    onPressed: node.isRunning
                        ? () => _testApi(node, '/api/config', context)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _testApi(
      NodeService node, String path, BuildContext pageContext) async {
    try {
      final result = await node.apiCall(path);
      if (pageContext.mounted) {
        _showResultDialog(pageContext, path, result);
      }
    } catch (e) {
      if (pageContext.mounted) {
        _showResultDialog(pageContext, path, {'error': e.toString()});
      }
    }
  }

  void _showResultDialog(
      BuildContext context, String path, Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('API: $path',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(result),
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
