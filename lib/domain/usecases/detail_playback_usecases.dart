/// 领域层：详情页·播放入口用例。
///
/// 链路：站点（allSources 按 key 解析）→ 模式判定 → 引擎/API → 详情内容 → 剧集/播放地址。
/// 对齐契约 §1.1（引擎选择规则）+ §3（`vod_play_from` / `vod_play_url` 解析）。
///
/// 模式分支（对齐 iOS `resolveSiteMode`）：
/// - apiEndpoint / zhanyuan → CMS V10 详情（`?ac=detail&ids=`），播放地址即直链；
/// - node / jsSpider / pythonSpider → Spider 引擎 `detailContent` / `playerContent`；
/// - jsSpider 由 QuickJS 顶替（G-03-B 决策：JSC 为 iOS 原生保留）。
library;

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../data/datasources/remote/all_sources_datasource.dart';
import '../../data/datasources/remote/cms_v10_datasource.dart';
import '../../data/datasources/remote/cms_v10_models.dart';
import '../../platform/runtime/quickjs_ffi.dart';
import '../../platform/spider/node_http_client.dart';
import '../../platform/spider/spider_engine_factory.dart';
import '../entities/playback/playback.dart';
import '../entities/remote_source/remote_source.dart';
import '../entities/spider/spider.dart';

/// 详情页·播放入口用例。
class DetailPlaybackUseCases {
  /// 构造。
  ///
  /// [loadAllSources] 注入站点聚合加载（清单 → allSources URL → 拉取解析），
  /// 便于表现层组装缓存/TTL 逻辑；引擎相关依赖均可注入（测试用 fake）。
  DetailPlaybackUseCases({
    required this.loadAllSources,
    SpiderEngineFactory engineFactory = const SpiderEngineFactory(),
    CmsV10Datasource? cmsDatasource,
    QuickJsNativeBridge? quickJsBridge,
    NodeHttpClient? nodeClient,
  })  : _engineFactory = engineFactory,
        _cmsDatasource = cmsDatasource,
        _quickJsBridge = quickJsBridge,
        _nodeClient = nodeClient;

  /// 站点聚合加载器（`Future<Result<AllSourcesContainer>>`）。
  final Future<Result<AllSourcesContainer>> Function() loadAllSources;

  final SpiderEngineFactory _engineFactory;
  final CmsV10Datasource? _cmsDatasource;
  final QuickJsNativeBridge? _quickJsBridge;
  final NodeHttpClient? _nodeClient;

  /// 加载详情播放数据。
  ///
  /// [siteKey] 即收藏/历史条目的 laiyuan；[initialIndex] 为续播入口传入的剧集索引。
  Future<Result<PlaybackDetail>> loadDetail({
    required String siteKey,
    required String vodId,
    int initialIndex = 0,
  }) async {
    if (siteKey.trim().isEmpty) {
      return const Err<PlaybackDetail>(ValidationFailure('站点 key 为空'));
    }
    if (vodId.trim().isEmpty) {
      return const Err<PlaybackDetail>(ValidationFailure('影片 ID 为空'));
    }

    final Result<AllSourcesContainer> sourcesResult = await loadAllSources();
    final Failure? sourcesFailure = sourcesResult.failureOrNull;
    if (sourcesFailure != null) return Err<PlaybackDetail>(sourcesFailure);
    final AllSourcesContainer? container = sourcesResult.valueOrNull;
    if (container == null) {
      return const Err<PlaybackDetail>(UnknownFailure('站点聚合为空'));
    }

    final SiteConfig? site = AllSourcesDatasource.findSite(container, siteKey);
    if (site == null) {
      return Err<PlaybackDetail>(ValidationFailure('未找到站点：$siteKey'));
    }

    switch (site.resolveSiteMode()) {
      case SiteMode.apiEndpoint:
      case SiteMode.zhanyuan:
        return _loadViaCms(site, vodId, initialIndex);
      case SiteMode.node:
      case SiteMode.jsSpider:
      case SiteMode.pythonSpider:
        return _loadViaSpider(site, vodId, initialIndex);
      case SiteMode.unsupported:
        return Err<PlaybackDetail>(
          UnsupportedFailure('站点「${site.name}」模式不支持（.jar / 未知类型）'),
        );
    }
  }

  /// 解析单集实际播放地址。
  ///
  /// - 直链媒体 → 原地址返回（免二次解析）；
  /// - API/站源站点 → 地址即播放地址（CMS 已归一）；
  /// - 脚本引擎站点 → `playerContent` 二次解析（对齐契约 §3.5）。
  Future<Result<PlayerContentResult>> resolvePlayUrl({
    required PlaybackDetail detail,
    required PlaybackEpisode episode,
  }) async {
    if (episode.isDirectMedia) {
      return Success<PlayerContentResult>(PlayerContentResult(url: episode.url));
    }

    final SiteMode mode = detail.site.resolveSiteMode();
    if (mode == SiteMode.apiEndpoint || mode == SiteMode.zhanyuan) {
      return Success<PlayerContentResult>(PlayerContentResult(url: episode.url));
    }

    final SpiderEngineType engineType = _effectiveEngineType(detail.site);
    final SpiderEngine engine;
    try {
      engine = _createEngine(detail.site, engineType);
    } catch (e) {
      return Err<PlayerContentResult>(_asFailure(e));
    }

    try {
      await _prepareEngine(engine, detail.site, engineType);
      final String flag =
          episode.from ?? (detail.froms.isNotEmpty ? detail.froms.first : '');
      final PlayerContentResult playerResult =
          await engine.callPlayerContent(detail.vod.vodId, flag, episode.url);
      return Success<PlayerContentResult>(playerResult);
    } catch (e) {
      return Err<PlayerContentResult>(_asFailure(e));
    } finally {
      await engine.dispose();
    }
  }

  // ─────────────── 内部：Spider 引擎路径 ───────────────

  Future<Result<PlaybackDetail>> _loadViaSpider(
    SiteConfig site,
    String vodId,
    int initialIndex,
  ) async {
    final SpiderEngineType engineType = _effectiveEngineType(site);
    final SpiderEngine engine;
    try {
      engine = _createEngine(site, engineType);
    } catch (e) {
      return Err<PlaybackDetail>(_asFailure(e));
    }

    try {
      await _prepareEngine(engine, site, engineType);
      final DetailContentResult detail = await engine.callDetailContent(vodId);
      final List<VodItem> list = detail.list ?? const <VodItem>[];
      if (list.isEmpty) {
        return Err<PlaybackDetail>(ParseFailure('详情为空：$vodId'));
      }
      return Success<PlaybackDetail>(
        PlaybackDetail.fromVod(
          site: site,
          vod: list.first,
          initialIndex: initialIndex,
        ),
      );
    } catch (e) {
      return Err<PlaybackDetail>(_asFailure(e));
    } finally {
      await engine.dispose();
    }
  }

  /// 创建引擎（工厂异常 → 上抛由调用方归一）。
  SpiderEngine _createEngine(SiteConfig site, SpiderEngineType engineType) =>
      _engineFactory.create(
        engineType,
        siteKey: site.key,
        baseUrl: site.api,
        nodeClient: _nodeClient,
        quickJsBridge: _quickJsBridge,
      );

  /// 准备引擎：脚本引擎先加载脚本（Node 桥 no-op），再注册蜘蛛。
  Future<void> _prepareEngine(
    SpiderEngine engine,
    SiteConfig site,
    SpiderEngineType engineType,
  ) async {
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
      await engine.loadScriptFromURL(trimmed);
    }
    await engine.registerSpider();
    if (!engine.isSpiderReady) {
      throw const SpiderFailure('蜘蛛注册失败（未找到 __JS_SPIDER__）');
    }
  }

  /// 引擎类型（jsSpider → QuickJS 顶替 JSC，G-03-B 决策）。
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

  // ─────────────── 内部：CMS V10 路径 ───────────────

  Future<Result<PlaybackDetail>> _loadViaCms(
    SiteConfig site,
    String vodId,
    int initialIndex,
  ) async {
    final CmsV10Datasource? cms = _cmsDatasource;
    if (cms == null) {
      return const Err<PlaybackDetail>(
        UnsupportedFailure('API/站源站点需要注入 CMS 数据源'),
      );
    }
    final String? base = site.api;
    if (base == null || base.trim().isEmpty) {
      return Err<PlaybackDetail>(ValidationFailure('站点「${site.name}」缺少 API 地址'));
    }

    final Result<CmsV10Detail> r = await cms.fetchDetail(base, vodId);
    final Failure? failure = r.failureOrNull;
    if (failure != null) return Err<PlaybackDetail>(failure);
    final CmsV10Detail? detail = r.valueOrNull;
    if (detail == null) {
      return const Err<PlaybackDetail>(ParseFailure('CMS 详情为空'));
    }
    return Success<PlaybackDetail>(
      PlaybackDetail.fromVod(
        site: site,
        vod: _toVodItem(detail),
        initialIndex: initialIndex,
      ),
    );
  }

  /// CMS 详情 → Spider `VodItem`（供统一 `PlaybackDetail.fromVod` 复用）。
  VodItem _toVodItem(CmsV10Detail detail) {
    final CmsV10Video v = detail.video;
    return VodItem(
      vodId: v.vodId,
      vodName: v.name,
      vodPic: v.pic,
      vodRemarks: v.remarks.isEmpty ? null : v.remarks,
      vodYear: v.year.isEmpty ? null : v.year,
      vodArea: v.area.isEmpty ? null : v.area,
      vodContent: detail.content.isEmpty ? null : detail.content,
      vodActor: detail.actors.isEmpty ? null : detail.actors,
      vodDirector: detail.director.isEmpty ? null : detail.director,
      vodPlayUrl: v.playUrl.isEmpty ? null : v.playUrl,
    );
  }

  /// 归一失败（`SpiderException` → `SpiderFailure`，其余走 [Failure.from]）。
  Failure _asFailure(Object e) {
    if (e is SpiderException) {
      return SpiderFailure(e.message, cause: e);
    }
    return Failure.from(e);
  }
}
