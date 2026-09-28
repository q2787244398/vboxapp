import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/node_service.dart';
import '../services/website_api.dart';

/// 网盘扫码登录页面。
/// 对应 bundle 中的 `/website/api/login/start|poll|cancel` 调用链。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _providers = [
    ('baidu', '百度网盘', Icons.cloud),
    ('y115', '115云盘', Icons.cloud),
    ('quark', '夸克', Icons.cloud),
    ('uc', 'UC网盘', Icons.cloud),
    ('tianyi', '天翼云盘', Icons.cloud),
    ('pan123', '123云盘', Icons.cloud),
    ('new139', '移动云盘', Icons.cloud),
    ('xunlei', '迅雷', Icons.cloud),
    ('guangya', '光鸭', Icons.cloud),
    ('woniu4k', '蜗牛', Icons.cloud),
    ('bilibili_all', 'B站', Icons.video_library),
    ('pikpak', 'PikPak', Icons.cloud),
    ('ali', '阿里云盘', Icons.cloud),
    ('emby', 'Emby', Icons.tv),
  ];

  String _selected = 'baidu';
  Timer? _pollTimer;
  String? _qrImageBase64;
  String? _msg;
  bool _busy = false;

  bool _isManualLoginProvider(String provider) =>
      provider == 'emby' || provider == 'ali';

  Future<void> _startLogin() async {
    final node = context.read<NodeService>();
    final api = WebsiteApiService(node);
    setState(() {
      _busy = true;
      _qrImageBase64 = null;
      _msg = null;
    });
    try {
      final result = await api.loginStart(_selected);
      final img = result['qrImage'] as String?;
      final taskId = result['taskId'] as String?;
      final msg = result['msg'] as String?;
      setState(() {
        _qrImageBase64 = img;
        _msg = msg ?? '请扫码确认';
      });
      if (img == null || img.isEmpty) return;
      if (_isManualLoginProvider(_selected)) return;
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pollLogin(api, taskId!),
      );
    } catch (e) {
      setState(() => _msg = '启动失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pollLogin(WebsiteApiService api, String taskId) async {
    try {
      final result = await api.loginPoll(_selected, taskId);
      final status = result['status'] as String?;
      if (status == 'ok' || status == 'success') {
        _pollTimer?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackbar(
            const Snackbar(content: Text('登录成功')),
          );
          Navigator.pop(context);
        }
      }
    } catch (_) {
      // 轮询失败不中断
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网盘登录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButton<String>(
            value: _selected,
            items: _providers
                .map((p) => DropdownMenuItem(
                      value: p.$1,
                      child: Row(
                        children: [
                          Icon(p.$3, size: 20),
                          const SizedBox(width: 8),
                          Text(p.$2),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selected = v!),
          ),
          const SizedBox(height: 24),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_qrImageBase64 != null) ...[
            _QrImage(base64: _qrImageBase64!),
            const SizedBox(height: 16),
            if (_msg != null) Text(_msg!),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _pollTimer?.cancel();
                final node = context.read<NodeService>();
                final api = WebsiteApiService(node);
                api.loginCancel('');
                setState(() => _qrImageBase64 = null);
              },
              child: const Text('取消'),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: _startLogin,
              child: const Text('开始登录'),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 16),
              Text(_msg!),
            ],
          ],
        ],
      ),
    );
  }
}

class _QrImage extends StatefulWidget {
  final String base64;
  const _QrImage({required this.base64});

  @override
  State<_QrImage> createState() => _QrImageState();
}

class _QrImageState extends State<_QrImage> {
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = base64Decode(widget.base64);
  }

  @override
  Widget build(BuildContext context) {
    if (_imageBytes == null) return const CircularProgressIndicator();
    return Image.memory(_imageBytes!, width: 240, height: 240);
  }
}