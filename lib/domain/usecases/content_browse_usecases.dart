/// 领域层：内容浏览用例（首页 / 分类 / 搜索，单源解析）。
///
/// 链路：站点（allSources 按 key 解析）→ 模式判定 → 引擎/API → 内容结果。
/// 对齐契约 §1.1（引擎选择规则）+ §3（返回结构）+ iOS `SpiderRepository` /
/// `CMSV10Helper`。
///
/// 模式分支（对齐 `DetailPlaybackUseCases`，同源解析口径）：
/// - apiEndpoint / zhanyuan → CMS V10（`?ac=list` / `?ac=videolist`）；
/// - node / jsSpider / pythonSpider → Spider 引擎 `homeContent` / `categoryContent` /
///   `searchContent`；
/// - jsSpider 由 QuickJS 顶替（G-03-B 决策：JSC 为 iOS 原生保留）。
library;

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../data/datasources/local/tg_search_config_store.dart';
import '../../data/datasources/remote/all_sources_datasource.dart';
import '../../data/datasources/remote/cms_v10_datasource.dart';
import '../../data/datasources/remote/cms_v10_models.dart';
import '../../platform/runtime/quickjs_ffi.dart';
import '../../platform/spider/node_http_client.dart';
import '../../platform/spider/spider_engine_factory.dart';
import '../entities/remote_source/remote_source.dart';
import '../entities/spider/spider.dart';

/// TG 搜索蜘蛛站点 key（对齐 iOS `SpiderManager.swift` L1394 的注入判定）。
const String _tgSearchSiteKey = 'js_TG搜索';

/// 内容浏览用例。
class ContentBrowseUseCases {
  /// 构造。
  ///
  /// [loadAllSources] 注入站点聚合加载（清单 → allSources URL → 拉取解析），
  /// 便于表现层组装缓存/TTL 逻辑；引擎相关依赖均可注入（测试用 fake）。
  ContentBrowseUseCases({
    required this.loadAllSources,
    SpiderEngineFactory engineFactory = const SpiderEngineFactory(),
    CmsV10Datasource? cmsDatasource,
    QuickJsNativeBridge? quickJsBridge,
    NodeHttpClient? nodeClient,
  })  : _engineFactory = engineFactory,
        _cmsDatasource = cmsDatasource,
        _quickJsBridge = quickJsBridge,
        _nodeClient = nodeClient;

  /// 站点聚合加载器。
  final Future<Result<AllSourcesContainer>> Function() loadAllSources;

  final SpiderEngineFactory _engineFactory;
  final CmsV10Datasource? _cmsDatasource;
  final QuickJsNativeBridge? _quickJsBridge;
  final NodeHttpClient? _nodeClient;

  /// 列出全部可浏览站点（源切换 UI）。
  Future<Result<List<SiteConfig>>> listSites() async {
    final Result<AllSourcesContainer> sourcesResult = await loadAllSources();
    final Failure? failure = sourcesResult.failureOrNull;
    if (failure != null) return Err<List<SiteConfig>>(failure);
    final AllSourcesContainer? container = sourcesResult.valueOrNull;
    if (container == null) {
      return const Err<List<SiteConfig>>(UnknownFailure('站点聚合为空'));
    }
    final List<SiteConfig> sites = container.sites
        .map((Map<String, Object?> raw) => SiteConfig.fromJson(raw))
        .where((SiteConfig s) => s.key.isNotEmpty)
        .toList(growable: false);
    if (sites.isEmpty) {
      return const Err<List<SiteConfig>>(UnknownFailure('无可用站点'));
    }
    return Success<List<SiteConfig>>(sites);
  }

  /// 首页内容（单源）。
  Future<Result<HomeContentResult>> homeContent(String siteKey) async {
    final _ResolvedSite? resolved = await _resolve(siteKey);
    if (resolved == null) {
      return const Err<HomeContentResult>(ValidationFailure('站点 key 为空'));
    }
    if (resolved.error != null) return Err<HomeContentResult>(resolved.error!);

    final SiteConfig site = resolved.site!;
    switch (site.resolveSiteMode()) {
      case SiteMode.apiEndpoint:
      case SiteMode.zhanyuan:
        return _cmsHome(site);
      case SiteMode.node:
      case SiteMode.jsSpider:
      case SiteMode.pythonSpider:
        return _spiderHome(site);
      case SiteMode.unsupported:
        return Err<HomeContentResult>(
          UnsupportedFailure('站点「${site.name}」模式不支持'),
        );
    }
  }

  /// 分类内容（单源，分页）。
  Future<Result<CategoryContentResult>> categoryContent(
    String siteKey, {
    String? tid,
    int page = 1,
  }) async {
    final _ResolvedSite? resolved = await _resolve(siteKey);
    if (resolved == null) {
      return const Err<CategoryContentResult>(ValidationFailure('站点 key 为空'));
    }
    if (resolved.error != null) {
      return Err<CategoryContentResult>(resolved.error!);
    }

    final SiteConfig site = resolved.site!;
    switch (site.resolveSiteMode()) {
      case SiteMode.apiEndpoint:
      case SiteMode.zhanyuan:
        return _cmsCategory(site, tid, page);
      case SiteMode.node:
      case SiteMode.jsSpider:
      case SiteMode.pythonSpider:
        return _spiderCategory(site, tid, page);
      case SiteMode.unsupported:
        return Err<CategoryContentResult>(
          UnsupportedFailure('站点「${site.name}」模式不支持'),
        );
    }
  }

  /// 分类列表（源分类胶囊）。
  Future<Result<List<VodCategory>>> categories(String siteKey) async {
    final _ResolvedSite? resolved = await _resolve(siteKey);
    if (resolved == null) {
      return const Err<List<VodCategory>>(ValidationFailure('站点 key 为空'));
    }
    if (resolved.error != null) {
      return Err<List<VodCategory>>(resolved.error!);
    }

    final SiteConfig site = resolved.site!;
    switch (site.resolveSiteMode()) {
      case SiteMode.apiEndpoint:
      case SiteMode.zhanyuan:
        return _cmsCategories(site);
      case SiteMode.node:
      case SiteMode.jsSpider:
      case SiteMode.pythonSpider:
        return _spiderCategories(site);
      case SiteMode.unsupported:
        return Err<List<VodCategory>>(
          UnsupportedFailure('站点「${site.name}」模式不支持'),
        );
    }
  }

  /// 搜索内容（单源，分页）。
  Future<Result<SearchContentResult>> searchContent(
    String siteKey,
    String keyword, {
    int page = 1,
  }) async {
    if (keyword.trim().isEmpty) {
      return const Err<SearchContentResult>(ValidationFailure('搜索关键词为空'));
    }
    final _ResolvedSite? resolved = await _resolve(siteKey);
    if (resolved == null) {
      return const Err<SearchContentResult>(ValidationFailure('站点 key 为空'));
    }
    if (resolved.error != null) {
      return Err<SearchContentResult>(resolved.error!);
    }

    final SiteConfig site = resolved.site!;
    switch (site.resolveSiteMode()) {
      case SiteMode.apiEndpoint:
      case SiteMode.zhanyuan:
        return _cmsSearch(site, keyword, page);
      case SiteMode.node:
      case SiteMode.jsSpider:
      case SiteMode.pythonSpider:
        return _spiderSearch(site, keyword, page);
      case SiteMode.unsupported:
        return Err<SearchContentResult>(
          UnsupportedFailure('站点「${site.name}」模式不支持'),
        );
    }
  }

  // ─────────────── 内部：站点解析 ───────────────

  Future<_ResolvedSite?> _resolve(String siteKey) async {
    final String key = siteKey.trim();
    if (key.isEmpty) return null;

    final Result<AllSourcesContainer> sourcesResult = await loadAllSources();
    final Failure? sourcesFailure = sourcesResult.failureOrNull;
    if (sourcesFailure != null) return _ResolvedSite.error(sourcesFailure);
    final AllSourcesContainer? container = sourcesResult.valueOrNull;
    final SiteConfig? site = container == null
        ? null
        : AllSourcesDatasource.findSite(container, key);
    if (site == null) {
      return _ResolvedSite.error(ValidationFailure('未找到站点：$key'));
    }
    return _ResolvedSite(site);
  }

  // ─────────────── 内部：CMS V10 路径 ───────────────

  Future<Result<HomeContentResult>> _cmsHome(SiteConfig site) async {
    final CmsV10Datasource? cms = _cmsDatasource;
    if (cms == null) {
      return const Err<HomeContentResult>(
        UnsupportedFailure('API/站源站点需要注入 CMS 数据源'),
      );
    }
    final String? base = site.api;
    if (base == null || base.trim().isEmpty) {
      return Err<HomeContentResult>(ValidationFailure('站点「${site.name}」缺少 API 地址'));
    }

    // 分类为尽力而为（失败不阻断首页列表）；列表为必需。
    final Result<List<CmsV10Category>> catResult = await cms.fetchCategories(base);
    final Result<List<CmsV10Video>> listResult = await cms.fetchVideos(base);
    final Failure? listFailure = listResult.failureOrNull;
    if (listFailure != null) return Err<HomeContentResult>(listFailure);

    final List<VodCategory> classes =
        (catResult.valueOrNull ?? const <CmsV10Category>[])
            .map((CmsV10Category c) => VodCategory(
                typeId: c.typeId, typeName: c.typeName))
            .toList(growable: false);
    final List<VodItem> list =
        listResult.valueOrNull!.map(_toVodItem).toList(growable: false);
    return Success<HomeContentResult>(
      HomeContentResult(classes: classes.isEmpty ? null : classes, list: list),
    );
  }

  Future<Result<List<VodCategory>>> _cmsCategories(SiteConfig site) async {
    final CmsV10Datasource? cms = _cmsDatasource;
    if (cms == null) {
      return const Err<List<VodCategory>>(
        UnsupportedFailure('API/站源站点需要注入 CMS 数据源'),
      );
    }
    final String? base = site.api;
    if (base == null || base.trim().isEmpty) {
      return Err<List<VodCategory>>(ValidationFailure('站点「${site.name}」缺少 API 地址'));
    }
    final Result<List<CmsV10Category>> r = await cms.fetchCategories(base);
    final Failure? failure = r.failureOrNull;
    if (failure != null) return Err<List<VodCategory>>(failure);
    return Success<List<VodCategory>>(
      r.valueOrNull!
          .map((CmsV10Category c) =>
              VodCategory(typeId: c.typeId, typeName: c.typeName))
          .toList(growable: false),
    );
  }

  Future<Result<CategoryContentResult>> _cmsCategory(
    SiteConfig site,
    String? tid,
    int page,
  ) async {
    final CmsV10Datasource? cms = _cmsDatasource;
    if (cms == null) {
      return const Err<CategoryContentResult>(
        UnsupportedFailure('API/站源站点需要注入 CMS 数据源'),
      );
    }
    final String? base = site.api;
    if (base == null || base.trim().isEmpty) {
      return Err<CategoryContentResult>(ValidationFailure('站点「${site.name}」缺少 API 地址'));
    }
    final Result<List<CmsV10Video>> r = await cms.fetchVideos(
      base,
      typeId: (tid == null || tid.trim().isEmpty) ? null : tid.trim(),
      page: page,
    );
    final Failure? failure = r.failureOrNull;
    if (failure != null) return Err<CategoryContentResult>(failure);
    return Success<CategoryContentResult>(
      CategoryContentResult(
        page: page,
        list: r.valueOrNull!.map(_toVodItem).toList(growable: false),
      ),
    );
  }

  Future<Result<SearchContentResult>> _cmsSearch(
    SiteConfig site,
    String keyword,
    int page,
  ) async {
    final CmsV10Datasource? cms = _cmsDatasource;
    if (cms == null) {
      return const Err<SearchContentResult>(
        UnsupportedFailure('API/站源站点需要注入 CMS 数据源'),
      );
    }
    final String? base = site.api;
    if (base == null || base.trim().isEmpty) {
      return Err<SearchContentResult>(ValidationFailure('站点「${site.name}」缺少 API 地址'));
    }
    final Result<List<CmsV10Video>> r =
        await cms.fetchVideos(base, keyword: keyword.trim(), page: page);
    final Failure? failure = r.failureOrNull;
    if (failure != null) return Err<SearchContentResult>(failure);
    return Success<SearchContentResult>(
      SearchContentResult(
        page: page,
        list: r.valueOrNull!.map(_toVodItem).toList(growable: false),
      ),
    );
  }

  /// CMS 视频 → Spider `VodItem`（供内容浏览统一复用）。
  VodItem _toVodItem(CmsV10Video v) => VodItem(
        vodId: v.vodId,
        vodName: v.name,
        vodPic: v.pic,
        vodRemarks: v.remarks.isEmpty ? null : v.remarks,
        vodYear: v.year.isEmpty ? null : v.year,
        vodArea: v.area.isEmpty ? null : v.area,
      );

  // ─────────────── 内部：Spider 引擎路径 ───────────────

  Future<Result<HomeContentResult>> _spiderHome(SiteConfig site) async {
    final SpiderEngine engine = _ensureEngine(site);
    try {
      await _prepareEngine(engine, site);
      return Success<HomeContentResult>(await engine.callHomeContent());
    } catch (e) {
      return Err<HomeContentResult>(_asFailure(e));
    } finally {
      await engine.dispose();
    }
  }

  Future<Result<List<VodCategory>>> _spiderCategories(SiteConfig site) async {
    final SpiderEngine engine = _ensureEngine(site);
    try {
      await _prepareEngine(engine, site);
      final HomeContentResult home = await engine.callHomeContent();
      return Success<List<VodCategory>>(home.classes ?? const <VodCategory>[]);
    } catch (e) {
      return Err<List<VodCategory>>(_asFailure(e));
    } finally {
      await engine.dispose();
    }
  }

  Future<Result<CategoryContentResult>> _spiderCategory(
    SiteConfig site,
    String? tid,
    int page,
  ) async {
    final SpiderEngine engine = _ensureEngine(site);
    try {
      await _prepareEngine(engine, site);
      return Success<CategoryContentResult>(
        await engine.callCategoryContent(tid ?? '', page, '{}'),
      );
    } catch (e) {
      return Err<CategoryContentResult>(_asFailure(e));
    } finally {
      await engine.dispose();
    }
  }

  Future<Result<SearchContentResult>> _spiderSearch(
    SiteConfig site,
    String keyword,
    int page,
  ) async {
    final SpiderEngine engine = _ensureEngine(site);
    try {
      await _prepareEngine(engine, site);
      return Success<SearchContentResult>(
        await engine.callSearchContent(keyword.trim(), page),
      );
    } catch (e) {
      return Err<SearchContentResult>(_asFailure(e));
    } finally {
      await engine.dispose();
    }
  }

  SpiderEngine _ensureEngine(SiteConfig site) {
    final SpiderEngineType engineType = _effectiveEngineType(site);
    return _engineFactory.create(
      engineType,
      siteKey: site.key,
      baseUrl: site.api,
      nodeClient: _nodeClient,
      quickJsBridge: _quickJsBridge,
    );
  }

  Future<void> _prepareEngine(SpiderEngine engine, SiteConfig site) async {
    final SpiderEngineType engineType = site.resolveEngineType()!;
    if (engineType == SpiderEngineType.quickJS ||
        engineType == SpiderEngineType.python) {
      final String? api = site.api;
      if (api == null || api.trim().isEmpty) {
        throw const ValidationFailure('蜘蛛脚本地址为空');
      }
      final String trimmed = api.trim();
      final bool isUrl =
          trimmed.startsWith('http://') || trimmed.startsWith('https://');
      if (!isUrl) {
        throw const UnsupportedFailure('本地插件脚本暂未接线（本批仅支持 http(s) 脚本 URL）');
      }
      // G-04：TG 搜索蜘蛛注入用户配置——对齐 iOS `SpiderManager` L1391-L1400
      // 在主脚本前 prepend `var __TG_CONFIG__ = {...};` 的语义；Flutter 以
      // `loadLibrary`（不检查注册）先建立全局变量，再加载主脚本。
      if (site.key == _tgSearchSiteKey &&
          engineType == SpiderEngineType.quickJS) {
        final String configJs = TGSearchConfigStore.shared.generateConfigJs();
        if (configJs.isNotEmpty) {
          await engine.loadLibrary(configJs);
        }
      }
      await engine.loadScriptFromURL(trimmed);
    }
    await engine.registerSpider();
    if (!engine.isSpiderReady) {
      throw const SpiderFailure('蜘蛛注册失败（未找到 __JS_SPIDER__）');
    }
  }

  SpiderEngineType _effectiveEngineType(SiteConfig site) {
    final SpiderEngineType? resolved = site.resolveEngineType();
    if (resolved == null) {
      throw SpiderException(
        SpiderErrorCode.unimplemented,
        '站点「${site.name}」无法解析引擎类型',
      );
    }
    return resolved == SpiderEngineType.javaScriptCore
        ? SpiderEngineType.quickJS
        : resolved;
  }

  Failure _asFailure(Object e) {
    if (e is SpiderException) {
      return SpiderFailure(e.message, cause: e);
    }
    return Failure.from(e);
  }
}

/// 站点解析结果（区分「key 为空」与「已解析/解析失败」）。
class _ResolvedSite {
  _ResolvedSite(this.site) : error = null;
  const _ResolvedSite.error(Failure this.error) : site = null;

  final SiteConfig? site;
  final Failure? error;
}