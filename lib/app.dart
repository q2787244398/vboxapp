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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/errors/failures.dart';
import 'core/network/http_client.dart';
import 'core/storage/storage_paths.dart';
import 'core/utils/logger.dart';
import 'core/utils/result.dart';
import 'data/datasources/local/database_manager.dart';
import 'data/datasources/local/log_file_sink.dart';
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
  /// 日志标签。
  static const String _logTag = 'app';

  bool _initialized = false;
  Object? _initError;

  /// 日志落盘 sink（A3；启动成功后常驻）。
  LogFileSink? _logSink;

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

  /// 初始化日志：按契约键配置闸门（`app_log_enabled` / `app_log_min_level`）
  /// 并启动落盘 sink（A3）。
  Future<void> _startLogging() async {
    final PrefsManager prefs = PrefsManager.instance;
    AppLog.configure(
      enabled: await prefs.getBool('app_log_enabled'),
      minLevel: LogLevel.fromValue(await prefs.getInt('app_log_min_level')),
    );
    _logSink = LogFileSink()..start();
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

      // ③ 日志（闸门 + 落盘）
      await _startLogging();
      AppLog.info(_logTag, '启动 v${AppInfo.version}+${AppInfo.buildNumber}');

      // ④ 数据层仓储 → 领域层用例
      // A2：网络可达性探针（平台层实现），注入全部 HTTP 客户端做离线短路。
      final ConnectivityNetworkInfo networkInfo = ConnectivityNetworkInfo();
      _favoriteUseCases = FavoriteUseCases(FavoriteRepositoryImpl());
      _historyUseCases = HistoryUseCases(HistoryRepositoryImpl());
      _subscriptionUseCases = SubscriptionUseCases(SubscriptionRepositoryImpl());
      _remoteSourceUseCases = RemoteSourceUseCases(
        RemoteSourceRepositoryImpl(
          datasource: RemoteManifestDatasource(
            client: HttpClient(networkInfo: networkInfo),
          ),
        ),
      );
      _allSourcesDatasource =
          AllSourcesDatasource(client: HttpClient(networkInfo: networkInfo));
      _cmsDatasource =
          CmsV10Datasource(client: HttpClient(networkInfo: networkInfo));
      _detailPlaybackUseCases = DetailPlaybackUseCases(
        loadAllSources: _loadAllSources,
        cmsDatasource: _cmsDatasource,
      );

      AppLog.info(_logTag, '初始化完成');
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (e) {
      AppLog.error(_logTag, '初始化失败', error: e);
      if (mounted) {
        setState(() => _initError = e);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_logSink?.stop());
    super.dispose();
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