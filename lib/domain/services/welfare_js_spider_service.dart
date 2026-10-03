/// 领域层：通用福利 JS Spider 服务（批次 H · H-03）。
///
/// 唯一真相源：iOS `vbox/WelfareRemote/WelfareJSSpiderService.swift`
///   · 设计目标（L7-L11）：新增福利平台只需远程源配置 + 上传 JS 脚本，
///     复用福利内容框架，不影响普通蜘蛛 / 网盘 / 其他福利平台；
///   · `service(for:)`（L35-L43）：按 `platformKey` 实例缓存；
///   · `ensureEngine()`（L70-L104）：下载脚本 → 创建引擎 → 加载 + 注册
///     → 调用 `init(config)`；失败记 `initError`；
///   · 抓取契约（L108-L269）：`fetchHomeContent` / `fetchCategoryContent` /
///     `fetchDetail` / `fetchSearch` / `fetchPlayerURL`（m3u8 走本地代理）；
///   · 剧集解析（L316-L436）：标准 / 非标准两种格式智能判定。
///
/// 移植口径与差异登记：
///   · JS 引擎走 **B-05 引擎工厂**（[SpiderEngineFactory.createForJsSite]：
///     JSC 主 / QuickJS 自动降级，降级可观测），而非 iOS 的 `JSSpiderEngine`；
///   · 引擎初始化 `init(config)` 由引擎层首次调用操作时自动执行（对齐
///     `JsCoreBridgeEngine._callSpiderApi`），本服务不再显式 `callInit`；
///   · `homeVideoContent` 兜底（iOS L126-L140）依赖 `callRawFunction`，Flutter
///     引擎层未暴露该能力 → 仅走 `homeContent`（差异登记，随 B 批次扩展）；
///   · m3u8 本地代理（SSL 绕过 + Brotli 解压）依赖 iOS `DoubanImageProxyServer`
///     等价物，Flutter 暂直接返回原地址 → 归 H-07 代理批次。
library;

import 'dart:async';

import '../../data/datasources/welfare/welfare_spider_loader.dart';
import '../../platform/spider/spider_engine_factory.dart';
import '../entities/spider/spider_engine.dart';
import '../entities/spider/spider_models.dart';
import '../entities/welfare/welfare.dart';
import 'fuli_base_service.dart';
import 'welfare_result_mapper.dart';

/// 通用福利 JS Spider 服务（远程 JS 脚本驱动福利平台）。
class WelfareJSSpiderService extends FuliBaseService {
  /// 构造（依赖可注入，便于单测）。
  ///
  /// [loader] 负责脚本下载 / 缓存（缺省真实加载器）；
  /// [engineProvider] 返回 JS 引擎（缺省走 B-05 D6 链：JSC 主 / QuickJS 降级；
  /// 测试注入 fake [SpiderEngine]）。
  WelfareJSSpiderService({
    required WelfarePlatform platform,
    WelfareSpiderLoader? loader,
    SpiderEngine Function()? engineProvider,
    void Function(String)? logSink,
  })  : _platform = platform,
        _loader = loader ?? WelfareSpiderLoader(),
        _log = logSink ?? print,
        super(
          platformKey: platform.platformKey,
          platformName: platform.name,
          defaultHosts: platform.defaultHosts,
        ) {
    _engineProvider = engineProvider ??
        () => const SpiderEngineFactory().createForJsSite(
              siteKey: platform.platformKey,
              onLog: _log,
            );
  }

  /// 按 `platformKey` 的实例缓存（对齐 iOS `NSCache` 语义）。
  static final Map<String, WelfareJSSpiderService> _cache =
      <String, WelfareJSSpiderService>{};

  /// 按平台取（或创建）服务实例（对齐 iOS `service(for:)`）。
  static WelfareJSSpiderService serviceFor(
    WelfarePlatform platform, {
    WelfareSpiderLoader? loader,
    SpiderEngine Function()? engineProvider,
    void Function(String)? logSink,
  }) =>
      _cache.putIfAbsent(
        platform.platformKey,
        () => WelfareJSSpiderService(
          platform: platform,
          loader: loader,
          engineProvider: engineProvider,
          logSink: logSink,
        ),
      );

  /// 清空实例缓存（装配重置 / 测试隔离用）。
  static void clearCache() => _cache.clear();

  final WelfarePlatform _platform;
  final WelfareSpiderLoader _loader;
  final void Function(String) _log;

  late final SpiderEngine Function() _engineProvider;

  final WelfareResultMapper _mapper = const WelfareResultMapper();

  SpiderEngine? _engine;
  String? _initError;
  Future<void>? _initFuture;

  /// 是否处于引擎就绪状态（对齐 iOS `engine != nil`）。
  bool get isEngineReady => _engine != null;

  /// 引擎初始化失败原因（失败后有值）。
  String? get engineInitError => _initError;

  // ─────────────── 引擎初始化（对齐 iOS `ensureEngine` L70-L104）───────────────

  /// 确保引擎已初始化（幂等；失败记 [engineInitError]，不抛给调用方）。
  Future<void> ensureEngine() async {
    if (_engine != null || _initError != null) return;
    _initFuture ??= _doInit();
    await _initFuture;
  }

  Future<void> _doInit() async {
    try {
      final WelfareSpiderScript script = await _loader.loadScript(_platform);
      final SpiderEngine engine = _engineProvider();
      await engine.loadScript(script.content);
      await engine.registerSpider();
      _engine = engine;
      _initError = null;
      _log('✅ [WelfareJS:${_platform.platformKey}] 引擎初始化成功');
    } catch (e) {
      _initError = e.toString();
      _log('❌ [WelfareJS:${_platform.platformKey}] 引擎初始化失败: $e');
    }
  }

  // ─────────────── FuliBaseService 实现（对齐 iOS L106-L269）───────────────

  @override
  String get currentHost =>
      _engine != null && defaultHosts.isNotEmpty ? defaultHosts.first : '';

  @override
  bool get isHostReady => _engine != null;

  /// 重新探测（重建引擎；自定义域名归 H-07，当前回退默认域名）。
  @override
  void reprobe() {
    _engine = null;
    _initError = null;
    _initFuture = null;
    unawaited(ensureEngine());
  }

  /// 重置域名（H-07 `WelfareDomainStore` 落地前仅回退默认域名重新探测）。
  @override
  void resetDomain() => reprobe();

  @override
  Future<FuliHomeResult> fetchHomeContent() async {
    await ensureEngine();
    final SpiderEngine? engine = _engine;
    if (engine == null) return FuliHomeResult.empty;
    try {
      final HomeContentResult result = await engine.callHomeContent();
      return _mapper.mapHome(result);
    } catch (e) {
      _log('❌ [WelfareJS:${_platform.platformKey}] fetchHomeContent: $e');
      return FuliHomeResult.empty;
    }
  }

  @override
  Future<FuliCategoryResult> fetchCategoryContent({
    required FuliCategory category,
    FuliCategory? subCategory,
    required int page,
  }) async {
    await ensureEngine();
    final SpiderEngine? engine = _engine;
    if (engine == null) {
      return FuliCategoryResult(videos: const <FuliVideo>[], page: page, hasMore: false);
    }
    final String tid = subCategory?.typeId ?? category.typeId;
    try {
      final CategoryContentResult result =
          await engine.callCategoryContent(tid, page, '{}');
      return _mapper.mapCategory(result);
    } catch (e) {
      _log('❌ [WelfareJS:${_platform.platformKey}] fetchCategoryContent: $e');
      return FuliCategoryResult(videos: const <FuliVideo>[], page: page, hasMore: false);
    }
  }

  @override
  Future<FuliDetail> fetchDetail(String vodId) async {
    await ensureEngine();
    final SpiderEngine? engine = _engine;
    if (engine == null) return _emptyDetail(vodId);
    try {
      final DetailContentResult result = await engine.callDetailContent(vodId);
      return _mapper.mapDetail(result);
    } catch (e) {
      _log('❌ [WelfareJS:${_platform.platformKey}] fetchDetail: $e');
      return _emptyDetail(vodId);
    }
  }

  @override
  Future<FuliSearchResult> fetchSearch({
    required String keyword,
    required int page,
  }) async {
    await ensureEngine();
    final SpiderEngine? engine = _engine;
    if (engine == null) {
      return FuliSearchResult(videos: const <FuliVideo>[], page: page, hasMore: false);
    }
    try {
      final SearchContentResult result = await engine.callSearchContent(keyword, page);
      return _mapper.mapSearch(result);
    } catch (e) {
      _log('❌ [WelfareJS:${_platform.platformKey}] fetchSearch: $e');
      return FuliSearchResult(videos: const <FuliVideo>[], page: page, hasMore: false);
    }
  }

  @override
  Future<FuliPlayerResult> fetchPlayerURL(FuliEpisode episode) async {
    await ensureEngine();

    String url = episode.url;
    Map<String, String> headers = const <String, String>{};
    int parse = 0;

    // 对齐 iOS L241-L266：JS 蜘蛛实现 playerContent 时调用它获取最终播放地址。
    final SpiderEngine? engine = _engine;
    if (engine != null && engine.isSpiderReady) {
      try {
        final PlayerContentResult pc =
            await engine.callPlayerContent('', platformName, url);
        final FuliPlayerResult mapped = _mapper.mapPlayer(pc);
        if (mapped.url.isNotEmpty) {
          url = mapped.url;
          headers = mapped.headers;
          parse = mapped.parse;
        }
      } catch (e) {
        _log('❌ [WelfareJS:${_platform.platformKey}] fetchPlayerURL: $e');
      }
    }

    // 对齐 iOS `processPlayerURL` L274-L293：合并默认 UA。
    // m3u8 本地代理（SSL 绕过 + Brotli）归 H-07，当前直接返回原地址。
    final Map<String, String> finalHeaders = <String, String>{...headers};
    finalHeaders['User-Agent'] ??= 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36';

    return FuliPlayerResult(url: url, headers: finalHeaders, parse: parse);
  }

  // ─────────────── 小工具 ───────────────

  FuliDetail _emptyDetail(String vodId) => FuliDetail(
        vodId: vodId,
        vodName: '',
        vodPic: '',
        vodContent: null,
        playFrom: platformName,
        episodes: const <FuliEpisode>[],
      );
}
