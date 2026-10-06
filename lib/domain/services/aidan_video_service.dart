/// 领域层：艾旦福利视频（`aidan_video`，CMS V10 固定站点）。
///
/// 唯一真相源：iOS `vbox/Services/AidanVideoService.swift`
///   · 固定 host `https://www.lovedan.net`（**忽略远程配置域名**，对齐 iOS 写死）；
///   · 请求头仅 `User-Agent: Mozilla/5.0` + `Referer: {host}/`（L24-L29）；
///   · API 基址 `{host}/api.php/provide/vod/`（L32）；
///   · `ac=list` 自适应分类 + `ac=detail&t=&pg=` 列表 / `ac=detail&ids=` 详情 /
///     `ac=detail&wd=&pg=` 搜索；
///   · 只保留视频类条目（`vod_play_url` 非空，对齐 `matchesContentType(.video)`）；
///   · `fetchPlayerURL`：`.m3u8/.mp4/.ts` 直链 → `parse 0`，其余 → `parse 1`。
///
/// 移植口径：解析逻辑直接复用 [RemoteCmsV10FuliService]（同为 CMS V10 契约），
/// 仅覆写站点请求头（[siteHeaderOverrides]）与该服务自身差异。
///
/// 差异登记：
///   · iOS `hasMore` 用 `videos.count >= 20`；Flutter 复用 CMS V10 的
///     `pagecount / limit` 判定（更准确，属**有意的行为改进**）。
library;

import '../../platform/spider/spider_http_bridge.dart';
import '../entities/welfare/welfare.dart';
import 'remote_cms_v10_service.dart';

/// 艾旦福利视频服务（`aidan_video`）。
class AidanFuliService extends RemoteCmsV10FuliService {
  /// 构造（[bridge] 供测试注入假传输）。
  AidanFuliService({super.bridge}) : super(platform: platform);

  /// 固定平台配置（对齐 iOS `AidanVideoService.init` 写死三元组）。
  static const WelfarePlatform platform = WelfarePlatform(
    platformKey: 'aidan_video',
    name: '艾旦福利视频',
    category: WelfarePlatformCategory.video,
    serviceType: 'aidan_video',
    defaultHosts: <String>['https://www.lovedan.net'],
    apiPath: '/api.php/provide/vod/',
  );

  /// 共享实例（对齐 iOS `AidanVideoService.shared`）。
  static AidanFuliService? _shared;

  /// 取（或创建）共享实例。
  static AidanFuliService instance({SpiderHttpBridge? bridge}) =>
      _shared ??= AidanFuliService(bridge: bridge);

  /// 清空共享实例（装配重置 / 测试隔离用）。
  static void clearCache() => _shared = null;

  @override
  Map<String, String>? get siteHeaderOverrides {
    final String host =
        currentHost.isEmpty ? 'https://www.lovedan.net' : currentHost;
    return <String, String>{
      'User-Agent': 'Mozilla/5.0',
      'Referer': host.endsWith('/') ? host : '$host/',
    };
  }
}
