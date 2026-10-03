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
///  - 原生盘（夸克 / 百度 / UC）→ 原生路链（待后续批次接线，本批次明确报错）。
library;

import '../../data/datasources/local/cloud_play_item_cache_store.dart';
import '../../data/datasources/local/prefs_manager.dart';
import '../../data/datasources/remote/node_pan_client.dart';
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
  })  : _client = client ?? NodePanClient(),
        _cache = cacheStore ??
            CloudPlayItemCacheStore(PrefsManager.instance),
        _controller = controller;

  final NodePanClient _client;
  final CloudPlayItemCacheStore _cache;
  PlayerController? _controller;

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

  /// 解析分享链接 → 条目列表（Node 托管盘）。
  Future<NodePanShare> resolveShare(CloudDriveType type, String shareUrl) async {
    _guardChannel(type);
    return _client.resolveShare(shareUrl);
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
    _guardChannel(type);
    final DateTime stamp = now ?? DateTime.now();
    final NodePanPlayData data = await _client.resolvePlay(entry.playID);
    final CloudPlayItem item = CloudPlayItem(
      provider: type.id,
      sourceKey: sourceKey ?? entry.playID,
      shareURL: shareUrl,
      resourceId: entry.playID,
      fileName: entry.name,
      playURL: data.url,
      headers: data.headers,
      compatibilityHint: 'node-proxy',
      preparedAt: stamp,
      updatedAt: stamp,
      source: 'node-pan',
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

  /// 通道守卫：非 Node 托管通道明确报错（对齐 iOS 的原生/Node 分支隔离）。
  void _guardChannel(CloudDriveType type) {
    switch (channelFor(type)) {
      case PanPlayChannel.nodePan:
        return;
      case PanPlayChannel.pgAli:
        throw const PanPlayException(
          '阿里云盘需 PG 4kz 路链（批次 F · F-09 接线）',
        );
      case PanPlayChannel.native:
        throw PanPlayException(
          '${type.displayName} 原生路链尚未接入（待后续批次）',
        );
      case PanPlayChannel.unsupported:
        throw PanPlayException('${type.displayName} 不支持网盘播放');
    }
  }
}
