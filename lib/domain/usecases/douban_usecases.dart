/// 领域层：豆瓣浏览用例（首页 / 榜单 / 分类浏览，并发拉取）。
///
/// 对齐 iOS `DoubanService` / `DoubanChartService` / `DoubanCategoryViewModel`：
/// - 首页聚合：banner（TOP250 前若干）+ 热门区块，**并发拉取**；
/// - 榜单：chart `top_list` 按分类 typeId 拉取；
/// - 分类浏览：rexxar 合集 + 客户端过滤 / 排序（对齐 iOS `applyFilters` / `applySort`）。
library;

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../data/datasources/remote/douban_datasource.dart';
import '../entities/douban/douban_models.dart';

/// 豆瓣浏览用例。
class DoubanUseCases {
  /// 构造（[datasource] 便于测试注入 fake）。
  DoubanUseCases({DoubanDatasource? datasource})
      : _datasource = datasource ?? DoubanDatasource();

  final DoubanDatasource _datasource;

  /// 分页大小。
  static const int pageSize = 20;

  /// 首页区块定义（标题 → collectionId），顺序即展示顺序。
  static const List<(String, String)> _homeSections = <(String, String)>[
    ('热门电影', 'movie_hot_gaia'),
    ('热门剧集', 'tv_real_time_hotest'),
    ('综艺', 'tv_variety_show'),
    ('动漫', 'tv_animation'),
  ];

  /// 首页聚合：banner（TOP250 前 8）+ 热门区块，并发拉取。
  Future<Result<DoubanHomeFeed>> homeFeed() async {
    try {
      final List<List<DoubanSubject>> results = await Future.wait(
        <Future<List<DoubanSubject>>>[
          _datasource.fetchCollection('movie_top250', start: 0, count: 8),
          for (final (_, String collectionId) in _homeSections)
            _datasource.fetchCollection(collectionId, start: 0, count: pageSize),
        ],
      );
      final List<DoubanHomeSection> sections = <DoubanHomeSection>[
        for (int i = 0; i < _homeSections.length; i++)
          if (results[i + 1].isNotEmpty)
            DoubanHomeSection(
              title: _homeSections[i].$1,
              items: results[i + 1],
            ),
      ];
      return Success<DoubanHomeFeed>(
        DoubanHomeFeed(banner: results.first, sections: sections),
      );
    } catch (e) {
      return Err<DoubanHomeFeed>(Failure.from(e));
    }
  }

  /// 分类排行榜（分页）。
  Future<Result<List<DoubanChartSubject>>> ranking(
    DoubanChartCategory category, {
    int page = 1,
  }) async {
    try {
      final int start = (page - 1) * pageSize;
      final List<DoubanChartSubject> list = await _datasource.fetchChartRanking(
        category,
        start: start,
        count: pageSize,
      );
      return Success<List<DoubanChartSubject>>(list);
    } catch (e) {
      return Err<List<DoubanChartSubject>>(Failure.from(e));
    }
  }

  /// 分类浏览（分页 + 客户端过滤 / 排序）。
  Future<Result<List<DoubanSubject>>> category(
    DoubanCategory category,
    DoubanFilterParams filters, {
    int page = 1,
  }) async {
    try {
      final int start = (page - 1) * pageSize;
      final List<DoubanSubject> list = await _datasource.fetchCollection(
        category.collectionId,
        start: start,
        count: pageSize,
      );
      final List<DoubanSubject> filtered = _applyFilters(list, filters);
      _applySort(filtered, filters.sort);
      return Success<List<DoubanSubject>>(filtered);
    } catch (e) {
      return Err<List<DoubanSubject>>(Failure.from(e));
    }
  }

  // ─────────────── 过滤 / 排序（对齐 iOS）───────────────

  List<DoubanSubject> _applyFilters(
    List<DoubanSubject> subjects,
    DoubanFilterParams filters,
  ) {
    List<DoubanSubject> result = subjects;

    if (filters.genre != null && filters.genre != '全部') {
      result = result
          .where((DoubanSubject s) => s.genres.contains(filters.genre))
          .toList(growable: false);
    }
    if (filters.year != null && filters.year != '全部') {
      result = result
          .where((DoubanSubject s) => _yearMatches(s.year, filters.year!))
          .toList(growable: false);
    }
    if (filters.region != null && filters.region != '全部') {
      result = result
          .where((DoubanSubject s) => _regionMatches(s, filters.region!))
          .toList(growable: false);
    }
    if (filters.platform != null && filters.platform != '全部') {
      result = result
          .where((DoubanSubject s) => _platformMatches(s, filters.platform!))
          .toList(growable: false);
    }
    return result;
  }

  void _applySort(List<DoubanSubject> subjects, DoubanSortType sort) {
    switch (sort) {
      case DoubanSortType.rating:
        subjects.sort((DoubanSubject a, DoubanSubject b) => b.rating.compareTo(a.rating));
      case DoubanSortType.year:
      case DoubanSortType.latest:
        subjects.sort(
          (DoubanSubject a, DoubanSubject b) =>
              (b.year ?? '').compareTo(a.year ?? ''),
        );
      case DoubanSortType.hot:
        // 豆瓣返回顺序即热度序，保持原样。
        break;
    }
  }

  bool _yearMatches(String? subjectYear, String year) {
    if (subjectYear == null) return false;
    switch (year) {
      case '2010年代':
        return subjectYear.compareTo('2010') >= 0 &&
            subjectYear.compareTo('2020') < 0;
      case '2000年代':
        return subjectYear.compareTo('2000') >= 0 &&
            subjectYear.compareTo('2010') < 0;
      case '90年代':
        return subjectYear.compareTo('1990') >= 0 &&
            subjectYear.compareTo('2000') < 0;
      case '更早':
        return subjectYear.compareTo('1990') < 0;
      default:
        return subjectYear == year;
    }
  }

  bool _regionMatches(DoubanSubject s, String region) {
    final String text = '${s.cardSubtitle ?? ''} ${s.intro ?? ''}';
    switch (region) {
      case '华语':
        return text.contains('中国大陆') ||
            text.contains('中国') ||
            text.contains('台湾') ||
            text.contains('香港') ||
            text.contains('华语');
      case '欧美':
        return text.contains('美国') ||
            text.contains('英国') ||
            text.contains('法国') ||
            text.contains('德国') ||
            text.contains('意大利') ||
            text.contains('西班牙') ||
            text.contains('加拿大');
      case '日本':
        return text.contains('日本');
      case '韩国':
        return text.contains('韩国');
      case '印度':
        return text.contains('印度');
      case '泰国':
        return text.contains('泰国');
      default:
        return true;
    }
  }

  bool _platformMatches(DoubanSubject s, String platform) {
    final String text = '${s.cardSubtitle ?? ''} ${s.intro ?? ''} ${s.title}';
    return text.contains(platform);
  }
}