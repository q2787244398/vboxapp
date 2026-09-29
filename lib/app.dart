/// 应用根组件。
///
/// 职责：
/// - 初始化依赖（PrefsManager / DatabaseManager）
/// - 形态判定（手机 / TV / 桌面）→ 选择对应 UI 布局
/// - 全局 Provider 注入
///
/// 唯一真相源：`docs/PROJECT_LAYOUT.md` + 方案 §2.4
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/datasources/local/database_manager.dart';
import 'data/datasources/local/prefs_manager.dart';
import 'presentation/ui_mode/ui_mode_resolver.dart';

class VBoxApp extends StatefulWidget {
  const VBoxApp({super.key});

  @override
  State<VBoxApp> createState() => _VBoxAppState();
}

class _VBoxAppState extends State<VBoxApp> {
  bool _initialized = false;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 初始化依赖。
  Future<void> _bootstrap() async {
    try {
      await PrefsManager.instance.init();
      await DatabaseManager.instance.database; // 触发建库/迁移
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initError = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('初始化失败：$_initError'),
            ),
          ),
        ),
      );
    }
    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return ChangeNotifierProvider<UiModeController>(
      create: (_) => UiModeController()..resolve(),
      child: const _RootRouter(),
    );
  }
}

/// 根据形态路由到对应布局。
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final UiModeController mode = context.watch<UiModeController>();
    // TODO(stage-1): 接入 presentation/{phone,tv,desktop} 三套布局
    return MaterialApp(
      title: 'VBox',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: Text('VBox · ${mode.mode.name}')),
        body: Center(
          child: Text(
            '形态：${mode.mode.name}\n（UI 布局待第 1 轮补齐）',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
