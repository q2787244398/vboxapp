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
///  - 阿里云盘 → PG 4kz 路链（批次 F · F-09 接线，本批次明确报错）；
///  - 原生盘（夸克 / 百度 / UC）→ 原生路链：**夸克已接入**（F-P01，
///    `QuarkNativeClient`：分享解析 → 文件列表 → 转存 → 取链）；**百度已接入**
///    （F-P02，`BaiduProxyClient` Worker 代理：parse → play）；**UC 已接入**
///    （F-P03，`UcNativeClient`：分享解析 → 文件列表 → 转存 → v2/play/download）。
library;

import '../../data/datasources/local/cloud_drive_credential_store.dart';
import '../../data/datasources/local/cloud_play_item_cache_store.dart';
import '../../data/datasources/local/prefs_manager.dart';
import '../../data/datasources/remote/baidu_proxy_client.dart';
import '../../data/datasources/remote/node_pan_client.dart';
import '../../data/datasources/remote/quark_native_client.dart';
import '../../data/datasources/remote/uc_native_client.dart';
import '../../domain/entities/cloud/baidu_proxy.dart';
import '../../domain/entities/cloud/cloud_drive.dart';
import '../../domain/entities/cloud/cloud_play_item.dart';
import '../../domain/entities/cloud/node_pan.dart';
import '../../domain/entities/player/player.dart';
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
    BaiduProxyClient? baiduClient,
    UcNativeClient? ucClient,
    Future<String> Function(CloudDriveType type)? cookieFor,
  })  : _client = client ?? NodePanClient(),
        _cache = cacheStore ??
            CloudPlayItemCacheStore(PrefsManager.instance),
        _controller = controller,
        _quark = quarkClient ?? QuarkNativeClient(),
        _baidu = baiduClient ?? BaiduProxyClient(),
        _uc = ucClient ?? UcNativeClient(),
        _cookieFor = cookieFor;

  final NodePanClient _client;
  final CloudPlayItemCacheStore _cache;
  PlayerController? _controller;

  /// 夸克原生分享链客户端（F-P01）。
  final QuarkNativeClient _quark;

  /// 百度专用代理客户端（F-P02，Worker 方案对齐 iOS `BaiduProxyClient`）。
  final BaiduProxyClient _baidu;

  /// UC 原生分享链客户端（F-P03，对齐 iOS `CloudDriveManager` UC 分支）。
  final UcNativeClient _uc;

  /// 网盘 Cookie 提供者（缺省读凭据安全存储 `cloud_drive_credentials_v1`）。
  final Future<String> Function(CloudDriveType type)? _cookieFor;

  /// 取指定网盘的 Cookie。
  Future<String> _cookie(CloudDriveType type) async {
    final Future<String> Function(CloudDriveType)? provider = _cookieFor;
    if (provider != null) return provider(type);
    try {
      final CloudDriveCredentialStore store =
          CloudDriveCredentialStore(PrefsManager.instance);
      final CloudDriveCredential? cred = await store.credential(type);
      return cred?.cookie ?? '';
    } catch (_) {
      return '';
    }
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
          try {
            final BaiduProxyResponse r =
                await _baidu.parseShareLink(url: shareUrl, cookie: cookie);
            final BaiduProxyPlayData? data = r.data;
            if (data == null || data.url.isEmpty) {
              throw const PanPlayException('百度分享解析失败');
            }
            return NodePanShare(
              title: data.fileName ?? '百度分享',
              entries: <NodePanEntry>[
                NodePanEntry(
                  playID: 'baidu',
                  name: data.fileName ?? '百度资源',
                ),
              ],
            );
          } on BaiduProxyException catch (e) {
            throw PanPlayException(e.message);
          }
        }
        if (type == CloudDriveType.uc) {
          final String cookie = await _cookie(type);
          final List<UcShareFile> files;
          try {
            files = await _uc.getFileList(shareUrl: shareUrl, cookie: cookie);
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
        throw const PanPlayException(
          '阿里云盘需 PG 4kz 路链（批次 F · F-09 接线）',
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
          } on QuarkNativeException catch (e) {
            throw PanPlayException(e.message);
          }
          headers = <String, String>{
            if (cookie.isNotEmpty) 'Cookie': cookie,
            'Referer': QuarkNativeClient.defaultReferer,
          };
          source = 'quark-native';
        } else if (type == CloudDriveType.baidu) {
          final String cookie = await _cookie(type);
          final BaiduProxyPlayData? data;
          try {
            final BaiduProxyResponse r = await _baidu.getPlayURL(
              shareURL: shareUrl,
              fsId: entry.playID == 'baidu' ? '' : entry.playID,
              cookie: cookie,
            );
            data = r.data;
          } on BaiduProxyException catch (e) {
            throw PanPlayException(e.message);
          }
          if (data == null || data.url.isEmpty) {
            throw const PanPlayException('百度未返回可用播放地址');
          }
          playURL = data.url;
          fileName = data.fileName ?? entry.name;
          final Map<String, String> h = <String, String>{...?data.headers};
          if (cookie.isNotEmpty) h['Cookie'] = cookie;
          headers = h;
          source = 'baidu-worker';
        } else if (type == CloudDriveType.uc) {
          final String cookie = await _cookie(type);
          final UcPlayResult r;
          try {
            r = await _uc.resolvePlayUrl(
              shareUrl: shareUrl,
              cookie: cookie,
              preferredFid: entry.playID,
            );
          } on UcNativeException catch (e) {
            throw PanPlayException(e.message);
          }
          playURL = r.url;
          fileName = entry.name;
          headers = r.headers;
          source = 'uc-native';
        } else {
          throw PanPlayException('${type.displayName} 原生路链尚未接入（待后续批次）');
        }
      case PanPlayChannel.pgAli:
        throw const PanPlayException(
          '阿里云盘需 PG 4kz 路链（批次 F · F-09 接线）',
        );
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
    );
    await _cache.store(item);
    return item;
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
      PlayerSource(
        url: item.playURL!,
        headers: item.headers,
        title: item.fileName.isEmpty ? null : item.fileName,
      ),
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
