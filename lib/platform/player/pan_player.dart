/// 平台层：网盘播放（pan 模式）编排（批次 F · F-08）。
///
/// 职责（对齐 iOS `CloudDriveManager.resolvePlayURL` 的 Node 分支 +
/// `NodePanResolver` + 统一播放缓存 `cloud_play_item_cache_v1`）：
///  - 分享链接 → 可播放条目（[NodePanClient.resolveShare]）；
///  - 条目 → 播放地址（[NodePanClient.resolvePlay]）；
///  - 解析结果落统一缓存（[CloudPlayItemCacheStore]，键 `provider|sourceKey`）；
///  - 交给 [PlayerController] 以**显式 `pan` 路由**打开播放。
///
/// 路由守卫（对齐 iOS `resolvePlayURL` 的分档）：
///  - Node 托管盘（115 / 123 / 139 / 189 / 迅雷 / 光鸭 / 蜗牛 / 夸克Node /
///    UC网盘Node / 百度网盘Node）→ Node 常驻系统链路；
///  - 阿里云盘 → PG 4kz 路链（F-P09，`AliyunAdriveClient`：ADrive 分享/转存 →
///    转码 m3u8 / 原画直链；未授权时明确报错）；
///  - 原生盘（夸克 / 百度 / UC）→ 原生路链：**夸克已接入**（F-P01，
///    `QuarkNativeClient`：分享解析 → 文件列表 → 转存 → 取链）；**百度已接入**
///    （F-P02，`BaiduIBoxClient` iBox 本机链：分享验证 → 多文件选集 → 转存 →
///    DLNA/locatedownload 取链；失败抛出，WebView 回退见 C3/Web-R1）；**UC 已接入**
///    （F-P03，`UcNativeClient`：分享解析 → 文件列表 → 转存 → v2/play/download）。
library;

import '../../data/datasources/local/cloud_drive_credential_store.dart';
import '../../data/datasources/local/cloud_play_item_cache_store.dart';
import '../../data/datasources/local/pg_auto_store.dart';
import '../../data/datasources/local/prefs_manager.dart';
import '../../data/datasources/remote/aliyun_adrive_client.dart';
import '../../data/datasources/remote/baidu_ibox_client.dart';
import '../../data/datasources/remote/node_pan_client.dart';
import '../../data/datasources/remote/quark_native_client.dart';
import '../../data/datasources/remote/uc_native_client.dart';
import '../../domain/entities/cloud/cloud_drive.dart';
import '../../domain/entities/cloud/cloud_play_item.dart';
import '../../domain/entities/cloud/node_pan.dart';
import '../../domain/entities/cloud/pg_auto.dart';
import '../../domain/entities/player/player.dart';
import 'pan_fallback_chain.dart';
import 'playback_route.dart';
import 'player_controller.dart';

/// 网盘播放路由通道（对齐 iOS `resolvePlayURL` 分支）。
enum PanPlayChannel {
  /// Node 常驻系统链路（`/spider/push/4/*`）。
  nodePan,

  /// 阿里云盘 PG 4kz 路链（批次 F · F-09）。
  pgAli,

  /// 原生盘路链（夸克 / 百度 / UC）。
  native,

  /// 不支持。
  unsupported,
}

/// 网盘播放入口不可用 / 业务错误。
class PanPlayException implements Exception {
  /// 构造。
  const PanPlayException(this.message);

  /// 展示文案。
  final String message;

  @override
  String toString() => 'PanPlayException($message)';
}

/// 网盘播放编排。
class PanPlayer {
  /// 构造（[client] / [cacheStore] / [controller] 均可注入；测试用替身）。
  PanPlayer({
    NodePanClient? client,
    CloudPlayItemCacheStore? cacheStore,
    PlayerController? controller,
    QuarkNativeClient? quarkClient,
    BaiduIBoxClient? baiduIBoxClient,
    UcNativeClient? ucClient,
    AliyunAdriveClient? aliyunClient,
    Future<String> Function(CloudDriveType type)? cookieFor,
  })  : _client = client ?? NodePanClient(),
        _cache = cacheStore ??
            CloudPlayItemCacheStore(PrefsManager.instance),
        _controller = controller,
        _quark = quarkClient ?? QuarkNativeClient(),
        _baiduIBox = baiduIBoxClient ?? BaiduIBoxClient(),
        _uc = ucClient ?? UcNativeClient(),
        _aliyun = aliyunClient ?? AliyunAdriveClient(),
        _cookieFor = cookieFor;

  final NodePanClient _client;
  final CloudPlayItemCacheStore _cache;
  PlayerController? _controller;

  /// 夸克原生分享链客户端（F-P01）。
  final QuarkNativeClient _quark;

  /// 百度 iBox 本机链客户端（F-P02，对齐 iOS `CloudDriveManager` 百度主路链）。
  final BaiduIBoxClient _baiduIBox;

  /// UC 原生分享链客户端（F-P03，对齐 iOS `CloudDriveManager` UC 分支）。
  final UcNativeClient _uc;

  /// 阿里云盘 PG 4kz 播放链客户端（F-P09，对齐 iOS `AliyunPgPlayManager`）。
  final AliyunAdriveClient _aliyun;

  /// 网盘 Cookie 提供者（缺省读凭据安全存储 `cloud_drive_credentials_v1`）。
  final Future<String> Function(CloudDriveType type)? _cookieFor;

  /// 取指定网盘的 Cookie。
  Future<String> _cookie(CloudDriveType type) async {
    final Future<String> Function(CloudDriveType)? provider = _cookieFor;
    if (provider != null) return provider(type);
    return (await _credential(type))?.cookie ?? '';
  }

  /// 取指定网盘凭据（缺省读凭据安全存储 `cloud_drive_credentials_v1`）。
  Future<CloudDriveCredential?> _credential(CloudDriveType type) async {
    try {
      final CloudDriveCredentialStore store =
          CloudDriveCredentialStore(PrefsManager.instance);
      return await store.credential(type);
    } catch (_) {
      return null;
    }
  }

  /// 百度 PCS 设备 Cookie（对齐 iOS `credential.extra["pcs_cookie"]`）。
  ///
  /// 注入 [cookieFor] 替身时无 extra，返回空串（行为等价 iOS `pair.pcs == nil`）。
  Future<String> _baiduPcsCookie() async {
    if (_cookieFor != null) return '';
    return (await _credential(CloudDriveType.baidu))?.extra['pcs_cookie'] ?? '';
  }

  /// 阿里云盘 PG 播放所需 Refresh Token（对齐 iOS `credential.refreshToken`）。
  Future<String> _aliyunRefreshToken() async =>
      (await _credential(CloudDriveType.ali))?.refreshToken ?? '';

  /// 阿里 PG 自动化配置（对齐 iOS `AliyunPgConfig.shared`，读取 `pg_ali_*`）。
  ///
  /// 读取失败回退契约缺省（与 iOS 未写入时的缺省行为一致：`enabled` 除外，
  /// 契约缺省关闭且 Flutter 不做首次写入）。
  Future<PgAutoConfig> _pgConfig() async {
    try {
      return await PgAutoStore(PrefsManager.instance).load();
    } catch (_) {
      return PgAutoConfig.defaults;
    }
  }

  /// UC TV Token（对齐 iOS `credential.extra["uc_tv_token"]`）。
  ///
  /// 注入 [cookieFor] 替身时无 extra，返回空串（等价 iOS 无 TV Token，
  /// 取链自动降级 v2/play → download_url）。
  Future<String> _ucTvToken() async {
    if (_cookieFor != null) return '';
    return (await _credential(CloudDriveType.uc))?.extra['uc_tv_token'] ?? '';
  }

  /// 播放控制器（缺省取全局单例）。
  PlayerController get controller => _controller ??= PlayerController.instance;

  /// 路由通道判定（对齐 iOS `resolvePlayURL`）。
  static PanPlayChannel channelFor(CloudDriveType type) {
    if (NodePanRouting.isNodeManaged(type)) return PanPlayChannel.nodePan;
    if (type == CloudDriveType.ali) return PanPlayChannel.pgAli;
    if (type == CloudDriveType.quark ||
        type == CloudDriveType.baidu ||
        type == CloudDriveType.uc) {
      return PanPlayChannel.native;
    }
    return PanPlayChannel.unsupported;
  }

  /// 解析分享链接 → 条目列表（Node 托管盘 / 夸克原生）。
  Future<NodePanShare> resolveShare(CloudDriveType type, String shareUrl) async {
    switch (channelFor(type)) {
      case PanPlayChannel.nodePan:
        return _client.resolveShare(shareUrl);
      case PanPlayChannel.native:
        if (type == CloudDriveType.quark) {
          final String cookie = await _cookie(type);
          final List<QuarkShareFile> files;
          try {
            files = await _quark.getFileList(
              shareUrl: shareUrl,
              cookie: cookie,
            );
          } on QuarkNativeException catch (e) {
            throw PanPlayException(e.message);
          }
          return NodePanShare(
            title: '夸克分享',
            entries: files
                .map((QuarkShareFile f) =>
                    NodePanEntry(playID: f.fid, name: f.fileName))
                .toList(growable: false),
          );
        }
        if (type == CloudDriveType.baidu) {
          final String cookie = await _cookie(type);
          final List<BaiduFileItem> files;
          try {
            files = await _baiduIBox.getFileList(
              shareUrl: shareUrl,
              cookie: cookie,
            );
          } on BaiduIBoxException catch (e) {
            throw PanPlayException(e.message);
          }
          return NodePanShare(
            title: '百度分享',
            entries: files
                .map((BaiduFileItem f) =>
                    NodePanEntry(playID: f.fsId, name: f.name))
                .toList(growable: false),
          );
        }
        if (type == CloudDriveType.uc) {
          final String cookie = await _cookie(type);
          final String tvToken = await _ucTvToken();
          final List<UcShareFile> files;
          try {
            files = await _uc.getFileList(
              shareUrl: shareUrl,
              cookie: cookie,
              tvToken: tvToken,
            );
          } on UcNativeException catch (e) {
            throw PanPlayException(e.message);
          }
          return NodePanShare(
            title: 'UC分享',
            entries: files
                .map((UcShareFile f) =>
                    NodePanEntry(playID: f.fid, name: f.fileName))
                .toList(growable: false),
          );
        }
        throw PanPlayException('${type.displayName} 原生路链尚未接入（待后续批次）');
      case PanPlayChannel.pgAli:
        final String refreshToken = await _aliyunRefreshToken();
        if (refreshToken.isEmpty) {
          throw const PanPlayException('阿里云盘未授权（缺少 Refresh Token），请先扫码登录');
        }
        final List<AliyunShareFile> files;
        try {
          files = await _aliyun.listPlayableFiles(
            shareUrl: shareUrl,
            refreshToken: refreshToken,
          );
        } on AliyunAdriveException catch (e) {
          throw PanPlayException(e.message);
        }
        return NodePanShare(
          title: '阿里云盘分享',
          entries: files
              .map((AliyunShareFile f) =>
                  NodePanEntry(playID: f.fileId, name: f.name))
              .toList(growable: false),
        );
      case PanPlayChannel.unsupported:
        throw PanPlayException('${type.displayName} 不支持网盘播放');
    }
  }

  /// 解析条目 → 播放地址，并写入统一缓存。
  ///
  /// [sourceKey] 缺省用 [NodePanEntry.playID]（配合 provider 构成缓存键）。
  Future<CloudPlayItem> prepare({
    required CloudDriveType type,
    required String shareUrl,
    required NodePanEntry entry,
    String? sourceKey,
    DateTime? now,
  }) async {
    final DateTime stamp = now ?? DateTime.now();
    final String playURL;
    final String fileName;
    final Map<String, String> headers;
    final String source;
    // 兜底线路（主=原画/兜底=m3u8 等拓扑，对齐 iOS `PlayResult`）。
    String? fallbackUrl;
    Map<String, String> fallbackHeaders = const <String, String>{};
    String fallbackSource = '';
    switch (channelFor(type)) {
      case PanPlayChannel.nodePan:
        final NodePanPlayData data = await _client.resolvePlay(entry.playID);
        playURL = data.url;
        fileName = entry.name;
        headers = data.headers;
        source = 'node-pan';
      case PanPlayChannel.native:
        if (type == CloudDriveType.quark) {
          final String cookie = await _cookie(type);
          try {
            final QuarkPlayResult r = await _quark.resolvePlayUrl(
              shareUrl: shareUrl,
              cookie: cookie,
              preferredFid: entry.playID,
            );
            playURL = r.url;
            fileName = r.fileName.isEmpty ? entry.name : r.fileName;
            headers = r.headers.isNotEmpty
                ? r.headers
                : <String, String>{
                    if (cookie.isNotEmpty) 'Cookie': cookie,
                    'Referer': QuarkNativeClient.defaultReferer,
                  };
            fallbackUrl = r.fallbackUrl;
            fallbackHeaders = r.fallbackHeaders;
            fallbackSource = r.fallbackSource;
          } on QuarkNativeException catch (e) {
            throw PanPlayException(e.message);
          }
          source = 'quark-native';
        } else if (type == CloudDriveType.baidu) {
          final String cookie = await _cookie(type);
          final String pcsCookie = await _baiduPcsCookie();
          final BaiduPlayResult r;
          try {
            r = await _baiduIBox.resolvePlayURL(
              shareUrl: shareUrl,
              bduss: cookie,
              fsId: entry.playID,
              pcsCookie: pcsCookie,
            );
          } on BaiduIBoxException catch (e) {
            throw PanPlayException(e.message);
          }
          playURL = r.url;
          fileName = entry.name;
          headers = r.headers;
          source = r.source;
        } else if (type == CloudDriveType.uc) {
          final String cookie = await _cookie(type);
          final String tvToken = await _ucTvToken();
          final UcPlayResult r;
          try {
            r = await _uc.resolvePlayUrl(
              shareUrl: shareUrl,
              cookie: cookie,
              preferredFid: entry.playID,
              tvToken: tvToken,
            );
          } on UcNativeException catch (e) {
            throw PanPlayException(e.message);
          }
          playURL = r.url;
          fileName = entry.name;
          headers = r.headers;
          fallbackUrl = r.fallbackUrl;
          fallbackHeaders = r.fallbackHeaders;
          fallbackSource = r.fallbackSource;
          source = 'uc-native';
        } else {
          throw PanPlayException('${type.displayName} 原生路链尚未接入（待后续批次）');
        }
      case PanPlayChannel.pgAli:
        final String refreshToken = await _aliyunRefreshToken();
        if (refreshToken.isEmpty) {
          throw const PanPlayException('阿里云盘未授权（缺少 Refresh Token），请先扫码登录');
        }
        final PgAutoConfig pgConfig = await _pgConfig();
        final AliyunPlayResult r;
        try {
          r = await _aliyun.resolvePlayUrl(
            shareUrl: shareUrl,
            refreshToken: refreshToken,
            preferredFileId: entry.playID,
            pgConfig: pgConfig,
          );
        } on AliyunAdriveException catch (e) {
          throw PanPlayException(e.message);
        }
        playURL = r.url;
        fileName = r.fileName.isEmpty ? entry.name : r.fileName;
        headers = r.headers;
        fallbackUrl = r.fallbackUrl;
        fallbackHeaders = r.fallbackHeaders;
        fallbackSource = r.fallbackSource;
        source = r.source;
      case PanPlayChannel.unsupported:
        throw PanPlayException('${type.displayName} 不支持网盘播放');
    }
    final CloudPlayItem item = CloudPlayItem(
      provider: type.id,
      sourceKey: sourceKey ?? entry.playID,
      shareURL: shareUrl,
      resourceId: entry.playID,
      fileName: fileName,
      playURL: playURL,
      headers: headers,
      compatibilityHint: source == 'node-pan' ? 'node-proxy' : source,
      preparedAt: stamp,
      updatedAt: stamp,
      source: source,
      fallbackURL: fallbackUrl,
      fallbackHeaders: fallbackHeaders,
      fallbackSource: fallbackSource,
    );
    await _cache.store(item);
    return item;
  }

  /// 网盘条目 → 播放源（主线路经 Go 代理落地 + 携带兜底线路）。
  ///
  /// 对齐 iOS `CloudDriveManager.resolveQuarkStream` / 各盘注册语义：HLS（m3u8）
  /// 与夸克原画直链经本地 Go 代理注入鉴权头后播放；代理不可用则降级直链。
  Future<PlayerSource> sourceFor(CloudPlayItem item, {String? title}) async {
    final String? url = item.playURL;
    if (url == null || url.isEmpty) {
      throw const PanPlayException('播放地址为空');
    }
    final bool quark = item.provider == CloudDriveType.quark.id;
    return resolvePanSource(
      primary: PanPlaybackLine(
        url: url,
        headers: item.headers,
        source: item.source.startsWith('quark-') ||
                item.source.startsWith('uc-') ||
                item.source == 'node-pan'
            ? ''
            : item.source,
        useQuarkProxy: quark,
      ),
      fallback: item.hasFallback
          ? PanPlaybackLine(
              url: item.fallbackURL!,
              headers: item.fallbackHeaders,
              source: item.fallbackSource,
              useQuarkProxy: quark,
            )
          : null,
      title: title,
    );
  }

  /// 解析并打开播放（显式 `pan` 路由）。
  Future<CloudPlayItem> open({
    required CloudDriveType type,
    required String shareUrl,
    required NodePanEntry entry,
    String? sourceKey,
    DateTime? now,
  }) async {
    final CloudPlayItem item = await prepare(
      type: type,
      shareUrl: shareUrl,
      entry: entry,
      sourceKey: sourceKey,
      now: now,
    );
    if (!item.hasPlayURL) {
      throw const PanPlayException('播放地址为空');
    }
    await controller.open(
      // 统一播放源落地：HLS 经 Go 代理注册 + 携带兜底线路（F21）。
      await sourceFor(item, title: item.fileName.isEmpty ? null : item.fileName),
      route: PlaybackRoute.pan,
    );
    return item;
  }

  /// 缓存汇总（对齐 iOS `cloudPlayItemSummary`）。
  Future<CloudPlayItemSummary> summary(CloudDriveType type, {DateTime? now}) =>
      _cache.summary(type.id, now: now);

  /// 失效标记（`playURL` / `expiresAt` 清空，来源追加原因）。
  Future<void> invalidate({
    required CloudDriveType type,
    required String sourceKey,
    String reason = 'invalidated',
    DateTime? now,
  }) =>
      _cache.invalidate(
        provider: type.id,
        sourceKey: sourceKey,
        reason: reason,
        now: now,
      );

  /// 过期清理（仅目标 provider）。
  Future<void> clearExpired(CloudDriveType type, {DateTime? now}) =>
      _cache.clearExpired(type.id, now: now);

  /// 按盘清空缓存。
  Future<void> clear(CloudDriveType type) => _cache.clear(type.id);
}
