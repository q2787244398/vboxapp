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

import 'core/errors/failures.dart';
import 'core/network/http_client.dart';
import 'core/storage/storage_paths.dart';
import 'core/utils/result.dart';
import 'data/datasources/local/database_manager.dart';
import 'data/datasources/local/prefs_manager.dart';
import 'data/datasources/remote/remote.dart';
import 'data/repositories/repositories.dart';
import 'domain/entities/remote_source/remote_source.dart';
import 'domain/usecases/usecases.dart';
import 'platform/system/system.dart';
import 'presentation/desktop/desktop_home_page.dart';
import 'presentation/phone/home_shelf_page.dart';
import 'presentation/tv/tv_home_page.dart';
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
  late final DetailPlaybackUseCases _detailPlaybackUseCases;
  late final AllSourcesDatasource _allSourcesDatasource;
  late final CmsV10Datasource _cmsDatasource;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 站点聚合加载（清单刷新 → allSources URL → 拉取解析）。
  Future<Result<AllSourcesContainer>> _loadAllSources() async {
    final Result<RemoteManifest> manifestResult =
        await _remoteSourceUseCases.refresh();
    final Failure? failure = manifestResult.failureOrNull;
    if (failure != null) return Err<AllSourcesContainer>(failure);

    final String? url =
        manifestResult.valueOrNull?.files[RemoteManifest.keyAllSources];
    if (url == null || url.isEmpty) {
      return const Err<AllSourcesContainer>(
        ValidationFailure('清单缺少 allSources 文件条目'),
      );
    }
    return _allSourcesDatasource.fetch(url);
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
      _allSourcesDatasource = AllSourcesDatasource(client: HttpClient());
      _cmsDatasource = CmsV10Datasource(client: HttpClient());
      _detailPlaybackUseCases = DetailPlaybackUseCases(
        loadAllSources: _loadAllSources,
        cmsDatasource: _cmsDatasource,
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
          create: (_) {
            final UiModeController c = UiModeController()..resolve();
            // G-02-C：Android 真机接线 —— 平台通道三重判定覆盖占位结果；
            // 桌面 / 测试环境不触碰通道（保持编译期常量兜底）。
            if (Platform.isAndroid) {
              c.resolveWithBridge(MethodChannelSystemBridge());
            }
            return c;
          },
        ),
        Provider<FavoriteUseCases>.value(value: _favoriteUseCases),
        Provider<HistoryUseCases>.value(value: _historyUseCases),
        Provider<SubscriptionUseCases>.value(value: _subscriptionUseCases),
        Provider<RemoteSourceUseCases>.value(value: _remoteSourceUseCases),
        Provider<DetailPlaybackUseCases>.value(value: _detailPlaybackUseCases),
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
    // G-01（UI 三形态）渐进交付：
    //   phone → 书架（v6.15）+ 远程源（v6.16）
    //   desktop → DesktopHomePage（v6.17，NavigationRail 宽屏布局）
    //   tv → TvHomePage（v6.18，T.7 焦点规范：TabBar 顶部导航 + FocusTraversalGroup）
    return MaterialApp(
      title: 'vbox',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: switch (mode.mode) {
        UiMode.phone => const HomeShelfPage(),
        UiMode.desktop => const DesktopHomePage(),
        UiMode.tv => const TvHomePage(),
      },
    );
  }
}