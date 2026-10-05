/// 应用根组件。
///
/// 职责：
/// - 初始化依赖（StoragePaths / PrefsManager / DatabaseManager）
/// - 组装数据层仓储实现 → 注入领域层用例
/// - 形态判定（竖屏 / 横屏 + 输入模态）→ 选择对应 UI 布局
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
import 'data/datasources/local/push_play_store.dart';
import 'data/datasources/local/subscribe_config_store.dart';
import 'data/datasources/local/tg_search_config_store.dart';
import 'data/datasources/local/tmdb_config_store.dart';
import 'data/datasources/local/welfare_domain_store.dart';
import 'data/datasources/local/welfare_proxy_store.dart';
import 'data/datasources/remote/remote.dart';
import 'data/repositories/repositories.dart';
import 'domain/entities/remote_source/remote_source.dart';
import 'domain/usecases/usecases.dart';
import 'platform/download/download.dart';
import 'platform/system/system.dart';
import 'presentation/profile/session_controller.dart';
import 'presentation/shell/home_shell_page.dart';
import 'presentation/theme/theme.dart';
import 'presentation/ui_mode/ui_mode_resolver.dart';
import 'presentation/welfare/welfare_controller.dart';
import 'presentation/welfare/welfare_platform_controller.dart';

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
  late final ContentBrowseUseCases _contentBrowseUseCases;
  late final SearchHistoryUseCases _searchHistoryUseCases;
  late final AllSourcesDatasource _allSourcesDatasource;
  late final CmsV10Datasource _cmsDatasource;

  /// 豆瓣浏览用例（A9：首页默认内容）。
  late final DoubanUseCases _doubanUseCases;

  /// TMDB 用例（G-06：详情页封面 / 演职增强；消费 `app_tmdb_*` 四契约键）。
  late final TmdbUseCases _tmdbUseCases;

  /// 皮肤控制器（A-03：消费 `app_skin_mode` / `app_skin_follows_system`）。
  late final VboxSkinController _skinController;

  /// 形态控制器（A-05：消费 `app_ui_form_override` + 平台通道三重判定）。
  late final UiFormController _uiFormController;

  /// 福利门控控制器（A8：消费 `app_welfare_enabled` / `app_welfare_unlocked`
  /// / `app_welfare_password`；控制底栏「福利」Tab 显隐）。
  late final WelfareController _welfareController;

  /// 福利平台配置控制器（H-01：消费 `fuli_remote_source_*` + `remote_default_manifest_url`；
  /// 福利页进入时 `bootstrap()` 恢复缓存并后台刷新）。
  late final WelfarePlatformController _welfarePlatformController;

  /// 本地账号会话控制器（I-02：SQLite `settings` 表的 `account` / `username`
  /// / `isLoggedIn` / `avatar_image`；纯本地账号，无服务端）。
  late final SessionController _sessionController;

  /// 下载管理器（G-02：全局下载队列 / 进度 / 管理浮层；消费 `download` 表）。
  late final DownloadManager _downloadManager;

  /// allSources 清单 URL（S-设1：脚本相对路径解析 base，对齐 iOS `subBaseURL`）。
  String? _allSourcesUrl;

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
    _allSourcesUrl = url;
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

      // ②' 皮肤（A-03：读契约键 → 主题工厂据此构建四皮肤）
      _skinController = VboxSkinController();
      await _skinController.load(PrefsManager.instance);

      // ②'' 形态（A-05：读契约键 `app_ui_form_override` → 用户显示模式覆盖；
      //      平台通道三重判定 TV / 触屏；桌面端走编译期常量兜底，不触碰通道）
      _uiFormController = UiFormController();
      final UiFormOverride formOverride = UiFormOverride.fromId(
        await PrefsManager.instance.uiFormOverride(),
      );
      await _uiFormController.resolveWithBridge(
        MethodChannelSystemBridge(),
        override: formOverride,
      );

      // ②''' 福利门控（A8：读契约键 `app_welfare_*` → 底栏「福利」Tab 显隐）
      _welfareController = WelfareController();
      await _welfareController.load(PrefsManager.instance);

      // ②'''' 本地账号会话（I-02：读 SQLite `settings` 表 → 个人中心登录态）
      _sessionController = SessionController();
      await _sessionController.load();

      // ②''''' 福利平台配置（H-01：消费 `fuli_remote_source_*` +
      //        `remote_default_manifest_url`；福利页进入时 bootstrap() 恢复缓存并后台刷新）
      _welfarePlatformController = WelfarePlatformController();

      // ②'''''' 福利代理 / 自定义域名（H-07：预加载共享实例，
      //        服务层 `allHosts` / `applyProxyIfNeeded` 与设置页即时消费）
      await WelfareProxyStore.shared.load();
      await WelfareDomainStore.shared.load();

      // ②''''''' 下载管理器（G-02：全局单例；存储走 `download` 表，目录走
      //        `StoragePaths.downloadDir`，依赖已在 ①/② 就绪）
      _downloadManager = DownloadManager();

      // ②'''''''' 推送播放（G-03：启动恢复 `push_play_items_v1` 契约键；
      //        与页面自调 `load()` 幂等，保证数据在进入页面前置就绪）
      await PushPlayStore.shared.load();

      // ②''''''''''' TG 搜索配置（G-04：启动恢复 `tg_search_*` 三契约键——
      //         代理地址 / 频道来源 / 自定义频道，供设置页与蜘蛛注入消费）
      await TGSearchConfigStore.shared.load();

      // ②''''''''''' 订阅配置（G-07：启动恢复 `subscribed_config_urls` /
      //         `active_subscription_index` / `cached_subscribe_config` 三契约键）
      await SubscribeConfigStore.shared.load();

      // ②'''''''''''' TMDB 配置（G-06：启动恢复 `app_enable_tmdb` /
      //         `app_tmdb_proxy_url` / `app_tmdb_use_token` / `app_tmdb_proxy_token`
      //         四契约键；敏感 Token 键经 PrefsManager 路由安全存储）
      await TmdbConfigStore.shared.load();

      // ③ 日志（闸门 + 落盘）
      await _startLogging();
      AppLog.info(_logTag, '启动 v${AppInfo.version}+${AppInfo.buildNumber}');

      // ④ 数据层仓储 → 领域层用例
      // A2：网络可达性探针（平台层实现），注入全部 HTTP 客户端做离线短路。
      final ConnectivityNetworkInfo networkInfo = ConnectivityNetworkInfo();
      _favoriteUseCases = FavoriteUseCases(FavoriteRepositoryImpl());
      _historyUseCases = HistoryUseCases(HistoryRepositoryImpl());
      _searchHistoryUseCases = SearchHistoryUseCases(SearchHistoryRepositoryImpl());
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
        scriptBaseUrl: () => _allSourcesUrl,
      );
      _contentBrowseUseCases = ContentBrowseUseCases(
        loadAllSources: _loadAllSources,
        cmsDatasource: _cmsDatasource,
        scriptBaseUrl: () => _allSourcesUrl,
      );
      // A9：首页默认内容 = 豆瓣推荐。
      _doubanUseCases = DoubanUseCases();
      // G-06：TMDB 详情增强（默认消费共享配置实例）。
      _tmdbUseCases = TmdbUseCases();

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
        ChangeNotifierProvider<UiFormController>.value(value: _uiFormController),
        ChangeNotifierProvider<VboxSkinController>.value(value: _skinController),
        ChangeNotifierProvider<WelfareController>.value(value: _welfareController),
        ChangeNotifierProvider<WelfarePlatformController>.value(
          value: _welfarePlatformController,
        ),
        ChangeNotifierProvider<SessionController>.value(value: _sessionController),
        ChangeNotifierProvider<DownloadManager>.value(value: _downloadManager),
        ChangeNotifierProvider<PushPlayStore>.value(value: PushPlayStore.shared),
        ChangeNotifierProvider<TGSearchConfigStore>.value(
          value: TGSearchConfigStore.shared,
        ),
        ChangeNotifierProvider<SubscribeConfigStore>.value(
          value: SubscribeConfigStore.shared,
        ),
        ChangeNotifierProvider<TmdbConfigStore>.value(
          value: TmdbConfigStore.shared,
        ),
        Provider<FavoriteUseCases>.value(value: _favoriteUseCases),
        Provider<HistoryUseCases>.value(value: _historyUseCases),
        Provider<SubscriptionUseCases>.value(value: _subscriptionUseCases),
        Provider<RemoteSourceUseCases>.value(value: _remoteSourceUseCases),
        Provider<DetailPlaybackUseCases>.value(value: _detailPlaybackUseCases),
        Provider<ContentBrowseUseCases>.value(value: _contentBrowseUseCases),
        Provider<SearchHistoryUseCases>.value(value: _searchHistoryUseCases),
        Provider<DoubanUseCases>.value(value: _doubanUseCases),
        Provider<TmdbUseCases>.value(value: _tmdbUseCases),
      ],
      child: const _RootRouter(),
    );
  }
}

/// 应用根路由。
///
/// A-08「页面树收敛」后：**单一页树** [HomeShellPage]（内部按 `UiForm` 产出双排布），
/// 本路由只负责主题装配；形态判定（竖/横 + 输入模态）下移到页树内部。
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final VboxSkinController skin = context.watch<VboxSkinController>();
    // A-03：皮肤 → 主题。`themeMode` 由 iOS 等价口径 `preferredColorScheme` 决定：
    //   非 null → 强制该亮/暗；null → 跟随系统（themeMode.system）。
    final Brightness? forced =
        VboxTheme.preferredBrightness(skin.skin, skin.followsSystem);
    final ThemeMode themeMode = switch (forced) {
      Brightness.light => ThemeMode.light,
      Brightness.dark => ThemeMode.dark,
      null => ThemeMode.system,
    };
    return MaterialApp(
      title: 'vbox',
      theme: VboxTheme.build(skin: skin.skin, brightness: Brightness.light),
      darkTheme: VboxTheme.build(skin: skin.skin, brightness: Brightness.dark),
      themeMode: themeMode,
      // A5：全端统一 iOS 回弹滚动（BouncingScrollPhysics + 无辉光过卷）。
      scrollBehavior: const VboxScrollBehavior(),
      home: const HomeShellPage(),
    );
  }
}