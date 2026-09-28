import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';

/// Detailed settings page (theme, history limits, advanced toggles).
class SettingsDetailPage extends StatefulWidget {
  const SettingsDetailPage({super.key});

  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<ConfigService, AppState>(
      builder: (context, config, app, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('设置'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('外观', [
                ListTile(
                  title: const Text('主题模式'),
                  trailing: Text(_themeLabel(app.themeMode)),
                  onTap: () => _pickTheme(context, app, config),
                ),
                SwitchListTile(
                  title: const Text('深色模式跟随系统'),
                  value: app.themeMode == ThemeMode.system,
                  onChanged: (v) {
                    app.setThemeMode(v ? ThemeMode.system : ThemeMode.dark);
                    config.setValue('themeMode', v ? 'system' : 'dark');
                  },
                ),
              ]),

              _section('播放器', [
                SwitchListTile(
                  title: const Text('自动播放'),
                  value: config.autoPlay,
                  onChanged: (v) => config.setValue('autoPlay', v),
                ),
                SwitchListTile(
                  title: const Text('显示封面'),
                  value: config.showCover,
                  onChanged: (v) => config.setValue('showCover', v),
                ),
                SwitchListTile(
                  title: const Text('硬件解码'),
                  value: config.hwDecoder,
                  onChanged: (v) => config.setValue('hwDecoder', v),
                ),
                ListTile(
                  title: const Text('缓冲时间 (ms)'),
                  trailing: Text('${config.bufferMs}',
                      style: const TextStyle(color: Colors.white54)),
                  onTap: () => _pickNumber(
                    context,
                    '缓冲时间',
                    config.bufferMs,
                    (v) => config.setValue('bufferMs', v),
                  ),
                ),
                ListTile(
                  title: const Text('播放历史上限'),
                  trailing: Text('${config.playHistoryLimit}',
                      style: const TextStyle(color: Colors.white54)),
                  onTap: () => _pickNumber(
                    context,
                    '播放历史上限',
                    config.playHistoryLimit,
                    (v) => config.setValue('playHistoryLimit', v),
                  ),
                ),
              ]),

              _section('高级', [
                SwitchListTile(
                  title: const Text('启用弹幕'),
                  value: config.enableDanmu,
                  onChanged: (v) => config.setValue('enableDanmu', v),
                ),
                SwitchListTile(
                  title: const Text('调试模式'),
                  value: config.enableDebug,
                  onChanged: (v) => config.setValue('enableDebug', v),
                ),
                ListTile(
                  title: const Text('清空播放历史',
                      style: TextStyle(color: Colors.redAccent)),
                  leading:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onTap: () async {
                    final db = context.read<DatabaseService>();
                    await db.clearWatchHistory();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已清空')));
                  },
                ),
              ]),
            ],
          ),
        );
      },
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

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  void _pickTheme(BuildContext context, AppState app, ConfigService config) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('主题模式'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              app.setThemeMode(ThemeMode.system);
              config.setValue('themeMode', 'system');
              Navigator.pop(context);
            },
            child: const Text('跟随系统'),
          ),
          SimpleDialogOption(
            onPressed: () {
              app.setThemeMode(ThemeMode.light);
              config.setValue('themeMode', 'light');
              Navigator.pop(context);
            },
            child: const Text('浅色'),
          ),
          SimpleDialogOption(
            onPressed: () {
              app.setThemeMode(ThemeMode.dark);
              config.setValue('themeMode', 'dark');
              Navigator.pop(context);
            },
            child: const Text('深色'),
          ),
        ],
      ),
    );
  }

  void _pickNumber(
      BuildContext context,
      String title,
      int initial,
      Function(int) apply) async {
    final controller = TextEditingController(text: initial.toString());
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入整数'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final parsed = int.tryParse(value ?? '');
    if (parsed != null) {
      apply(parsed);
    }
  }
}
