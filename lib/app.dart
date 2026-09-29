/// 应用根组件。
///
/// 职责：
/// - 初始化依赖（StoragePaths / PrefsManager / DatabaseManager）
/// - 组装数据层仓储实现 → 注入领域层用例
/// - 形态判定（手机 / TV / 桌面）→ 选择对应 UI 布局
/// - 全局 Provider 注入
///
/// 唯一真相源：方案 §2.4（目录结构落地快照见附录 B）
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/network/http_client.dart';
import 'core/storage/storage_paths.dart';
import 'data/datasources/local/database_manager.dart';
import 'data/datasources/local/prefs_manager.dart';
import 'data/datasources/remote/remote_manifest_datasource.dart';
import 'data/repositories/repositories.dart';
import 'domain/usecases/usecases.dart';
import 'presentation/ui_mode/ui_mode_resolver.dart';

class VBoxApp extends StatefulWidget {
  const VBoxApp({super.key});

  @override
  State<VBoxApp> createState() => _VBoxAppState();
}

class _VBoxAppState extends State<VBoxApp> {
  bool _initialized = false;
  Object? _initError;

  // 用例层实例（数据层仓储在此完成组装）
  late final FavoriteUseCases _favoriteUseCases;
  late final HistoryUseCases _historyUseCases;
  late final SubscriptionUseCases _subscriptionUseCases;
  late final RemoteSourceUseCases _remoteSourceUseCases;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 初始化依赖。
  Future<void> _bootstrap() async {
    try {
      // ① 目录布局（核心层纯 Dart，根目录由平台层注入）
      final Directory root = await getApplicationSupportDirectory();
      StoragePaths.configure(root.path);
      await StoragePaths.ensureLayout();

      // ② 存储层
      await PrefsManager.instance.init();
      await DatabaseManager.instance.database; // 触发建库/迁移

      // ③ 数据层仓储 → 领域层用例
      _favoriteUseCases = FavoriteUseCases(FavoriteRepositoryImpl());
      _historyUseCases = HistoryUseCases(HistoryRepositoryImpl());
      _subscriptionUseCases = SubscriptionUseCases(SubscriptionRepositoryImpl());
      _remoteSourceUseCases = RemoteSourceUseCases(
        RemoteSourceRepositoryImpl(
          datasource: RemoteManifestDatasource(client: HttpClient()),
        ),
      );

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

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UiModeController>(
          create: (_) => UiModeController()..resolve(),
        ),
        Provider<FavoriteUseCases>.value(value: _favoriteUseCases),
        Provider<HistoryUseCases>.value(value: _historyUseCases),
        Provider<SubscriptionUseCases>.value(value: _subscriptionUseCases),
        Provider<RemoteSourceUseCases>.value(value: _remoteSourceUseCases),
      ],
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
    // TODO(G-01/stage-1): 接入 presentation/{phone,tv,desktop} 三套布局
    //   登记于 docs/VBOX_PLAN_v6.12.md 附录 C（缺口登记表），阻塞项：UI 三形态未实现
    //   解除条件：presentation 层布局文件交付
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