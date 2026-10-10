/// 数据层：CMS V10 远程数据源。
///
/// 只做「请求 + 解析 + 归一」，不含业务规则（业务规则在用例层）。
/// 失败一律以 `Failure` 返回，不向调用方抛异常。
library;

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/json_utils.dart';
import '../../../core/utils/result.dart';
import 'cms_v10_models.dart';

/// CMS V10 数据源。
class CmsV10Datasource {
  /// 构造（[client] 便于测试注入 MockClient）。
  CmsV10Datasource({
    required HttpClient client,
    Map<String, String> headers = const <String, String>{},
  })  : _client = client,
        _headers = headers;

  final HttpClient _client;
  final Map<String, String> _headers;

  /// 默认每页条数（契约 §6）。
  static const int defaultPageSize = 20;

  /// 分类列表（`?ac=list`）。
  Future<Result<List<CmsV10Category>>> fetchCategories(String baseUrl) async {
    final Result<Map<String, Object?>> body =
        await _getJson(baseUrl, <String, String>{'ac': 'list'});
    final Failure? failure = body.failureOrNull;
    if (failure != null) return Err<List<CmsV10Category>>(failure);

    final Map<String, Object?> json =
        body.valueOrNull ?? const <String, Object?>{};
    final List<CmsV10Category> items = JsonUtils.asMapList(json['class'])
        .map((Map<String, Object?> j) => CmsV10Category.fromJson(j))
        .toList(growable: false);
    if (items.isEmpty) {
      return const Err<List<CmsV10Category>>(
        ParseFailure('分类为空（检查站点地址或该站是否支持 at=json）'),
      );
    }
    return Success<List<CmsV10Category>>(items);
  }

  /// 影片列表（`?ac=videolist&pg=N[&t=分类][&wd=关键词]`）。
  Future<Result<List<CmsV10Video>>> fetchVideos(
    String baseUrl, {
    String? typeId,
    int page = 1,
    String? keyword,
  }) async {
    if (page < 1) {
      return const Err<List<CmsV10Video>>(ValidationFailure('页码必须 ≥ 1'));
    }
    final Map<String, String> params = <String, String>{
      'ac': 'videolist',
      'pg': '$page',
    };
    if (typeId != null && typeId.trim().isNotEmpty) {
      params['t'] = typeId.trim();
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      params['wd'] = keyword.trim();
    }

    final Result<Map<String, Object?>> body = await _getJson(baseUrl, params);
    final Failure? failure = body.failureOrNull;
    if (failure != null) return Err<List<CmsV10Video>>(failure);

    final Map<String, Object?> json =
        body.valueOrNull ?? const <String, Object?>{};
    final String host = Uri.tryParse(baseUrl)?.host ?? '';
    final List<CmsV10Video> items = JsonUtils.asMapList(json['list'])
        .map((Map<String, Object?> j) => CmsV10Video.fromJson(j, host))
        .toList(growable: false);
    return Success<List<CmsV10Video>>(items);
  }

  /// 详情（`?ac=detail&ids=<vod_id>`）。
  Future<Result<CmsV10Detail>> fetchDetail(String baseUrl, String vodId) async {
    if (vodId.trim().isEmpty) {
      return const Err<CmsV10Detail>(ValidationFailure('影片 ID 为空'));
    }
    final Result<Map<String, Object?>> body = await _getJson(
      baseUrl,
      <String, String>{'ac': 'detail', 'ids': vodId.trim()},
    );
    final Failure? failure = body.failureOrNull;
    if (failure != null) return Err<CmsV10Detail>(failure);

    final Map<String, Object?> json =
        body.valueOrNull ?? const <String, Object?>{};
    final List<Map<String, Object?>> list = JsonUtils.asMapList(json['list']);
    if (list.isEmpty) {
      return Err<CmsV10Detail>(ParseFailure('详情为空：ids=${vodId.trim()}'));
    }
    final String host = Uri.tryParse(baseUrl)?.host ?? '';
    return Success<CmsV10Detail>(CmsV10Detail.fromJson(list.first, host));
  }

  // ── 内部 ──

  /// 组装接口地址（[jsonParam] 控制是否附加 `at=json`，保留站点自定义查询参数）。
  ///
  /// 返回 null 表示地址非法（非 http/https 或缺少 host）。
  Uri? buildUri(String baseUrl, Map<String, String> params,
      {bool jsonParam = true}) {
    final Uri? base = Uri.tryParse(baseUrl.trim());
    if (base == null) return null;
    if (base.scheme != 'http' && base.scheme != 'https') return null;
    if (base.host.isEmpty) return null;
    final Map<String, String> query = <String, String>{
      ...base.queryParameters,
      if (jsonParam) 'at': 'json',
      ...params,
    };
    return base.replace(queryParameters: query);
  }

  Future<Result<Map<String, Object?>>> _getJson(
    String baseUrl,
    Map<String, String> params,
  ) async {
    // 参数降级链（对齐 iOS `tryFetchJSON` 裸参语义）：
    // ① 裸参直连（iOS ac=home / ac=list / ac=videolist 均不带 at=json；
    //    部分网盘 CMS 的 provide/vod 不认 at=json，强拼会得 XML/错误页）；
    // ② 裸参响应非 JSON（老 CMS 默认 XML）→ 重试带 at=json。
    final Uri? plain = buildUri(baseUrl, params, jsonParam: false);
    if (plain == null) {
      return const Err<Map<String, Object?>>(
        ValidationFailure('站点地址非法（需 http/https 绝对地址）'),
      );
    }
    final Result<Map<String, Object?>> first = await _attempt(plain);
    final Failure? firstFailure = first.failureOrNull;
    if (firstFailure == null) return first;

    final Uri? forced = buildUri(baseUrl, params);
    if (forced == null || forced == plain) return first;
    final Result<Map<String, Object?>> retry = await _attempt(forced);
    final Failure? retryFailure = retry.failureOrNull;
    if (retryFailure == null) return retry;

    // 两次都失败：按原始错误收敛（裸参错误更贴近站点真实形态）。
    return first;
  }

  Future<Result<Map<String, Object?>>> _attempt(Uri uri) async {
    try {
      final HttpClientResponse res = await _client.get(
        uri,
        headers: _headers.isEmpty ? null : _headers,
      );
      if (!res.isOk) {
        return Err<Map<String, Object?>>(
          NetworkFailure(
            'HTTP ${res.statusCode}：$uri',
            code: ErrorCode.httpStatus,
          ),
        );
      }
      final Map<String, Object?>? json = JsonUtils.tryDecodeMap(res.text);
      if (json == null) {
        return Err<Map<String, Object?>>(
          ParseFailure('响应不是 JSON 对象：$uri'),
        );
      }
      return Success<Map<String, Object?>>(json);
    } catch (e) {
      return Err<Map<String, Object?>>(Failure.from(e));
    }
  }
}
