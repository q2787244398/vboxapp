/// 领域层：站源（zhanyuan）原生搜索用例。
///
/// 对齐 iOS `ZhanyuanSearchService.searchAllZhanyuan`：
/// - 站点来源**由表现层注入**（DB 优先、内存回退——对应 iOS
///   `queryActiveZhanyuanSites()` + `loadZhanyuanSitesFromMemory()` 回退）；
/// - 意见并发分批（每批 `maxConcurrency = 30`），逐批 `onBatch` 流式回调，
///   `onLog` 供诊断日志；
/// - 搜索前写搜索历史（注入，失败不阻断搜索）。
///
/// 单站搜索与详情解析的底层逻辑在平台层 [ZhanyuanSearchService]（Dart 原生
/// HTML/XPath），本 usecase 只做编排放大盘；腾讯原生 Spider 见
/// `TencentVideoNativeSpider`（不参与本 usecase，走详情播放入口）。
library;

import 'dart:math' show min;

import '../../data/models/zhanyuan.dart';
import '../../platform/spider/zhanyuan_search_service.dart';
import '../entities/spider/spider_models.dart';

/// 站源原生搜索用例。
class ZhanyuanSearchUseCases {
  /// 构造。
  ///
  /// [loadSites] 注入站点加载（表现层负责「DB 优先 → 内存回退」逻辑）；
  /// [addSearchHistory] 注入搜索历史落库（可空，失败不阻断搜索）；
  /// [service] 注入单站搜索服务（测试可传 fake transport 桥）。
  ZhanyuanSearchUseCases({
    required this.loadSites,
    this.addSearchHistory,
    ZhanyuanSearchService? service,
  }) : _service = service ?? ZhanyuanSearchService();

  /// 站点加载器（对齐 iOS「SQLite 查询 → SpiderManager 内存回退」）。
  final Future<List<Zhanyuan>> Function() loadSites;

  /// 搜索历史写入（对齐 iOS `addSearchHistory`）。
  final Future<void> Function(String keyword)? addSearchHistory;

  final ZhanyuanSearchService _service;

  /// 并发搜索所有启用站源，逐批流式回调结果。
  ///
  /// [onBatch] 每个非空结果批回调一次（对齐 iOS `onBatch`）；[onLog] 诊断日志。
  Future<void> searchAll(
    String keyword, {
    required void Function(List<VodItem>) onBatch,
    void Function(String)? onLog,
  }) async {
    final void Function(String) log = onLog ?? (_) {};
    final List<Zhanyuan> sites = await loadSites();
    log('zhanyuan 查询: ${sites.length} 个站点');

    if (sites.isEmpty) {
      log('⚠️ zhanyuan 无可用站点，跳过');
      return;
    }

    await addSearchHistory?.call(keyword);

    int successCount = 0;
    int failCount = 0;
    const int maxConcurrency = 30;

    for (int start = 0; start < sites.length; start += maxConcurrency) {
      final List<Zhanyuan> batch = sites.sublist(
        start,
        min(start + maxConcurrency, sites.length),
      );
      final List<(Zhanyuan, List<VodItem>)> results = await Future.wait(
        batch.map((Zhanyuan site) async {
          try {
            final List<VodItem> items =
                await _service.searchZhanyuan(site, keyword);
            return (site, items);
          } catch (_) {
            return (site, <VodItem>[]);
          }
        }),
      );

      for (final (Zhanyuan site, List<VodItem> items) in results) {
        if (items.isNotEmpty) {
          log('✅ zhanyuan[${site.name}] +${items.length}条');
          successCount++;
          onBatch(items);
        } else {
          log('⚠️ zhanyuan[${site.name}] 无结果');
          failCount++;
        }
      }
    }

    log('zhanyuan 搜索完成: 成功$successCount/失败$failCount/总计${sites.length}');
  }
}