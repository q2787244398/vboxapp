/// 数据层：豆瓣远程数据源。
///
/// 逆向来源：iOS `vbox/Services/DoubanService.swift`（rexxar API）与
/// `DoubanChartService.swift`（chart top_list API）。
/// - rexxar：`https://m.douban.com/rexxar/api/v2/subject_collection/{id}/items`
/// - chart：`https://movie.douban.com/j/chart/top_list?type={typeId}...`
///
/// 解析容错沿用 [DoubanSubject.fromJson] / [DoubanChartSubject.fromJson]，
/// 传输层只负责请求与 JSON 解码，不参与过滤/排序（属用例层）。
library;

import '../../../core/errors/exceptions.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/json_utils.dart';
import '../../../domain/entities/douban/douban_models.dart';

/// 豆瓣远程数据源。
class DoubanDatasource {
  /// 构造（[client] 便于测试注入 MockClient）。
  DoubanDatasource({HttpClient? client})
      : _client = client ?? HttpClient();

  /// rexxar API 基址（对齐 iOS `DoubanService.baseURL`）。
  static const String baseURL = 'https://m.douban.com/rexxar/api/v2';

  /// chart 排行榜 API（对齐 iOS `DoubanChartService`）。
  static const String chartBase = 'https://movie.douban.com/j/chart/top_list';

  /// rexxar 请求头（对齐 iOS：Referer + Accept JSON）。
  static const Map<String, String> _rexxarHeaders = <String, String>{
    'Referer': 'https://movie.douban.com',
    'Accept': 'application/json',
  };

  /// chart 请求头（对齐 iOS：UA 由 HttpClient 注入，此处只补 Referer/Accept）。
  static const Map<String, String> _chartHeaders = <String, String>{
    'Accept': 'application/json',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Referer': 'https://movie.douban.com/chart',
  };

  final HttpClient _client;

  /// 拉取合集条目（rexxar `subject_collection`）。
  ///
  /// 非 2xx 视为访问受限（对齐 iOS 403/302 → 抛错）。
  Future<List<DoubanSubject>> fetchCollection(
    String collectionId, {
    int start = 0,
    int count = 20,
  }) async {
    final Uri uri = Uri.parse(
      '$baseURL/subject_collection/$collectionId/items?start=$start&count=$count',
    );
    final HttpClientResponse res = await _client.get(uri, headers: _rexxarHeaders);
    if (!res.isOk) {
      throw NetworkException(
        '豆瓣 API 访问受限 (HTTP ${res.statusCode})',
        code: ErrorCode.httpStatus,
      );
    }
    final Map<String, Object?>? json = JsonUtils.tryDecodeMap(res.text);
    if (json == null) {
      throw const ParseException('豆瓣合集响应非 JSON', code: ErrorCode.parse);
    }
    return JsonUtils.asMapList(json['subject_collection_items'])
        .map(DoubanSubject.fromJson)
        .toList(growable: false);
  }

  /// 拉取分类排行榜（chart `top_list`，返回 JSON 数组）。
  Future<List<DoubanChartSubject>> fetchChartRanking(
    DoubanChartCategory category, {
    int start = 0,
    int count = 20,
  }) async {
    final Uri uri = Uri.parse(
      '$chartBase?type=${category.typeId}&interval_id=100:90&action='
      '&start=$start&limit=$count',
    );
    final HttpClientResponse res = await _client.get(uri, headers: _chartHeaders);
    if (!res.isOk) {
      throw NetworkException(
        '豆瓣榜单访问受限 (HTTP ${res.statusCode})',
        code: ErrorCode.httpStatus,
      );
    }
    final List<Object?>? raw = JsonUtils.tryDecodeList(res.text);
    if (raw == null) {
      throw const ParseException('豆瓣榜单响应非 JSON 数组', code: ErrorCode.parse);
    }
    final List<Map<String, Object?>> items =
        raw.whereType<Map>().map(JsonUtils.asMap).toList(growable: false);
    return <DoubanChartSubject>[
      for (int i = 0; i < items.length; i++)
        DoubanChartSubject.fromJson(items[i], start + i + 1),
    ];
  }
}