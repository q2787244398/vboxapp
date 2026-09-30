/// 数据层：远程站点聚合（all_sources.json）数据源。
///
/// 契约：`contract/schema/manifest_v1.json` §`$defs.allSources`
/// 逆向来源：iOS `vbox/Services/RemoteSourceConfigManager.swift`
///   - 拉取地址：清单 `files.allSources`；
///   - 代理降级链：ghfast → gh-proxy → 直连（对齐 iOS `proxyHosts`）；
///   - 校验链：HTTP 2xx → JSON 对象 → 顶层对象（7 键均可选）。
library;

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/json_utils.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/remote_source/remote_source.dart';
import '../../../domain/entities/spider/spider.dart';

/// 远程站点聚合数据源。
class AllSourcesDatasource {
  /// 构造。
  AllSourcesDatasource({
    required HttpClient client,
    Map<String, String> headers = const <String, String>{},
  })  : _client = client,
        _headers = headers;

  final HttpClient _client;
  final Map<String, String> _headers;

  /// 拉取并解析 allSources。
  ///
  /// 按代理降级链依次尝试（主代理 → 备用代理 → 直连），任一成功即返回；
  /// 全部失败时返回最后一次失败原因。
  Future<Result<AllSourcesContainer>> fetch(
    String url, {
    bool forceRefresh = false,
  }) async {
    final String raw = url.trim();
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const Err<AllSourcesContainer>(
        ValidationFailure('allSources 地址非法（需 http/https 绝对地址）'),
      );
    }

    Failure? lastFailure;
    for (final String candidate in RemoteSourceStrategy.candidates(raw)) {
      final Result<AllSourcesContainer> r =
          await _fetchOne(candidate, forceRefresh: forceRefresh);
      final Failure? f = r.failureOrNull;
      if (f == null) return r;
      lastFailure = f;
    }
    return Err<AllSourcesContainer>(
      lastFailure ?? const UnknownFailure('allSources 拉取失败'),
    );
  }

  /// 按站点 key（契约字段 `key`，详情页 laiyuan 即此值）查找站点配置。
  static SiteConfig? findSite(AllSourcesContainer container, String key) {
    final String k = key.trim();
    if (k.isEmpty) return null;
    for (final Map<String, Object?> raw in container.sites) {
      if ((raw['key'] ?? '').toString() == k) {
        return SiteConfig.fromJson(raw);
      }
    }
    return null;
  }

  Future<Result<AllSourcesContainer>> _fetchOne(
    String candidate, {
    required bool forceRefresh,
  }) async {
    try {
      final HttpClientResponse res = await _client.get(
        Uri.parse(candidate),
        headers: <String, String>{
          ..._headers,
          if (forceRefresh) 'cache-control': 'no-cache',
        },
      );
      if (!res.isOk) {
        return Err<AllSourcesContainer>(
          NetworkFailure(
            'HTTP ${res.statusCode}：$candidate',
            code: ErrorCode.httpStatus,
          ),
        );
      }

      final Map<String, Object?>? json = JsonUtils.tryDecodeMap(res.text);
      if (json == null) {
        return const Err<AllSourcesContainer>(
          ParseFailure('allSources 不是 JSON 对象'),
        );
      }
      return Success<AllSourcesContainer>(AllSourcesContainer.fromJson(json));
    } catch (e) {
      return Err<AllSourcesContainer>(Failure.from(e));
    }
  }
}
