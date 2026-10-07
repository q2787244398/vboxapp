/// 领域层：豆瓣实体与分类/筛选配置。
///
/// 逆向来源：iOS `vbox/Services/DoubanService.swift`（rexxar API）、
/// `vbox/Services/DoubanChartService.swift`（chart top_list API）。
///
/// 本批只做「浏览」所需实体：条目（subject）、榜单条目（chart subject）、
/// 榜单分类（chart category）、大分类（category）+ 筛选参数（filter params）。
/// 演职人员 / 详情大图 / 图片代理留待后续批次（D-05 详情页）。
library;

import '../../../core/utils/json_utils.dart';

/// 豆瓣条目（rexxar `subject_collection_items` 单项）。
class DoubanSubject {
  /// 构造。
  const DoubanSubject({
    required this.id,
    required this.title,
    this.coverUrl,
    this.rating = 0,
    this.ratingCount,
    this.year,
    this.genres = const <String>[],
    this.cardSubtitle,
    this.intro,
  });

  /// 从 JSON 解析（容错：字段缺失/类型不稳均不抛异常）。
  factory DoubanSubject.fromJson(Map<String, Object?> j) {
    final Map<String, Object?> rating = JsonUtils.asMap(j['rating']);
    return DoubanSubject(
      id: JsonUtils.pickStringOr(j, 'id', ''),
      title: JsonUtils.pickStringOr(j, 'title', ''),
      coverUrl: _normalizeCover(_bestCover(j)),
      rating: JsonUtils.asDouble(rating['value']) ?? 0,
      ratingCount: JsonUtils.asInt(rating['count']),
      year: JsonUtils.pickString(j, 'year'),
      genres: JsonUtils.asList(j['genres']).map((Object? e) => '$e').toList(),
      cardSubtitle: JsonUtils.pickString(j, 'card_subtitle'),
      intro: JsonUtils.pickString(j, 'intro'),
    );
  }

  final String id;

  /// 标题。
  final String title;

  /// 归一后的封面 URL（可能为 null）。
  final String? coverUrl;

  /// 评分（缺省 0 表示无评分）。
  final double rating;

  /// 评分人数。
  final int? ratingCount;

  /// 年份。
  final String? year;

  /// 类型列表。
  final List<String> genres;

  /// 卡片副标题。
  final String? cardSubtitle;

  /// 简介。
  final String? intro;

  /// 是否带评分。
  bool get hasRating => rating > 0;

  /// 类型文案（` / ` 连接）。
  String get genreText => genres.join(' / ');

  /// 封面优先级：`photos_gadget` → `cover_url` → `cover.{url,large,medium,small}`
  /// → `pic.{large,normal,medium,small}`。
  ///
  /// `pic` 兜底对齐 iOS：综艺 / 动漫 / 英美剧等 `subject_collection`（`tv_variety_show`、
  /// `tv_animation`、`tv_american`…）**不返回** `cover`/`cover_url`/`photos_gadget`，
  /// 封面仅存在于 `pic.large`。iOS 走 `fetchCollectionWithTVCovers`（逐条补拉详情封面），
  /// Flutter 直接取同一条目内已有的 `pic` 字段，无需额外请求即可拿到同一张封面。
  static String? _bestCover(Map<String, Object?> j) {
    final String? gadget = JsonUtils.pickString(j, 'photos_gadget');
    if (gadget != null && gadget.isNotEmpty) return gadget;
    final String? coverUrl = JsonUtils.pickString(j, 'cover_url');
    if (coverUrl != null && coverUrl.isNotEmpty) return coverUrl;
    final Map<String, Object?> cover = JsonUtils.pickMap(j, 'cover');
    final String? fromCover = JsonUtils.pickString(cover, 'url') ??
        JsonUtils.pickString(cover, 'large') ??
        JsonUtils.pickString(cover, 'medium') ??
        JsonUtils.pickString(cover, 'small');
    if (fromCover != null && fromCover.isNotEmpty) return fromCover;
    final Map<String, Object?> pic = JsonUtils.pickMap(j, 'pic');
    return JsonUtils.pickString(pic, 'large') ??
        JsonUtils.pickString(pic, 'normal') ??
        JsonUtils.pickString(pic, 'medium') ??
        JsonUtils.pickString(pic, 'small');
  }

  /// 封面 URL 归一：补 `https:` / `https://` 前缀。
  static String? _normalizeCover(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }
}

/// 豆瓣榜单条目（chart `top_list` API 单项）。
class DoubanChartSubject {
  /// 构造。
  const DoubanChartSubject({
    required this.id,
    required this.rank,
    required this.title,
    this.coverUrl,
    this.rating = 0,
    this.ratingCount,
    this.year,
    this.info,
    this.detailUrl,
  });

  /// 从 JSON 解析（[fallbackRank] 为原数组缺省 `rank` 时按序号补位）。
  factory DoubanChartSubject.fromJson(Map<String, Object?> j, int fallbackRank) {
    final String? score = JsonUtils.pickString(j, 'score');
    return DoubanChartSubject(
      id: JsonUtils.pickStringOr(j, 'id', ''),
      rank: JsonUtils.pickInt(j, 'rank', fallback: fallbackRank),
      title: JsonUtils.pickStringOr(j, 'title', ''),
      coverUrl: _normalizeCover(JsonUtils.pickString(j, 'cover_url')),
      rating: double.tryParse(score ?? '') ?? 0,
      ratingCount: JsonUtils.asInt(j['vote_count']),
      year: _firstFour(JsonUtils.pickString(j, 'release_date')),
      info: JsonUtils.asList(j['types']).map((Object? e) => '$e').join(' / '),
      detailUrl: JsonUtils.pickString(j, 'url'),
    );
  }

  final String id;

  /// 排名（1 起）。
  final int rank;

  final String title;

  final String? coverUrl;

  /// 评分。
  final double rating;

  /// 评分人数。
  final int? ratingCount;

  /// 年份（取 `release_date` 前 4 位）。
  final String? year;

  /// 类型/地区文案。
  final String? info;

  /// 详情页 URL。
  final String? detailUrl;

  bool get hasRating => rating > 0;

  static String? _normalizeCover(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return trimmed;
  }

  static String? _firstFour(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    return trimmed.length >= 4 ? trimmed.substring(0, 4) : trimmed;
  }
}

/// 榜单分类（chart 按 typeId 拉取）。
class DoubanChartCategory {
  /// 构造。
  const DoubanChartCategory({required this.name, required this.typeId});

  final String name;
  final int typeId;

  /// 全部榜单分类（对齐 iOS `DoubanChartService.ChartCategory.all`）。
  static const List<DoubanChartCategory> all = <DoubanChartCategory>[
    DoubanChartCategory(name: '剧情', typeId: 11),
    DoubanChartCategory(name: '喜剧', typeId: 24),
    DoubanChartCategory(name: '动作', typeId: 5),
    DoubanChartCategory(name: '爱情', typeId: 13),
    DoubanChartCategory(name: '科幻', typeId: 17),
    DoubanChartCategory(name: '动画', typeId: 25),
    DoubanChartCategory(name: '悬疑', typeId: 10),
    DoubanChartCategory(name: '惊悚', typeId: 19),
    DoubanChartCategory(name: '恐怖', typeId: 20),
    DoubanChartCategory(name: '纪录片', typeId: 1),
    DoubanChartCategory(name: '短片', typeId: 23),
    DoubanChartCategory(name: '音乐', typeId: 14),
    DoubanChartCategory(name: '歌舞', typeId: 7),
    DoubanChartCategory(name: '家庭', typeId: 28),
    DoubanChartCategory(name: '儿童', typeId: 8),
    DoubanChartCategory(name: '传记', typeId: 2),
    DoubanChartCategory(name: '历史', typeId: 4),
    DoubanChartCategory(name: '战争', typeId: 22),
    DoubanChartCategory(name: '犯罪', typeId: 3),
    DoubanChartCategory(name: '西部', typeId: 27),
    DoubanChartCategory(name: '奇幻', typeId: 16),
    DoubanChartCategory(name: '冒险', typeId: 15),
    DoubanChartCategory(name: '灾难', typeId: 12),
    DoubanChartCategory(name: '武侠', typeId: 29),
    DoubanChartCategory(name: '古装', typeId: 30),
    DoubanChartCategory(name: '运动', typeId: 18),
    DoubanChartCategory(name: '黑色电影', typeId: 31),
  ];
}

/// 豆瓣大分类（分类浏览用，含筛选预设）。
class DoubanCategory {
  /// 构造。
  const DoubanCategory({
    required this.type,
    required this.name,
    required this.collectionId,
    required this.genres,
    required this.years,
    required this.platforms,
    required this.regions,
  });

  final String type;
  final String name;
  final String collectionId;
  final List<String> genres;
  final List<String> years;
  final List<String> platforms;
  final List<String> regions;

  static const List<String> _commonYears = <String>[
    '全部', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019',
    '2018', '2017', '2010年代', '2000年代', '90年代', '更早',
  ];

  /// 全部大分类（对齐 iOS `DoubanCategoryConfig.allCategories`）。
  static const List<DoubanCategory> all = <DoubanCategory>[
    DoubanCategory(
      type: 'movie',
      name: '电影',
      collectionId: 'movie_hot_gaia',
      genres: <String>[
        '全部', '喜剧', '爱情', '动作', '科幻', '悬疑', '恐怖', '动画', '剧情',
        '犯罪', '冒险', '奇幻', '战争', '历史', '传记', '音乐', '家庭', '武侠', '古装',
      ],
      years: _commonYears,
      platforms: <String>[
        '全部', 'Netflix', 'HBO', 'BBC', 'Hulu', 'Apple TV+', 'Disney+',
        'Amazon', 'YouTube', '院线',
      ],
      regions: <String>['全部', '华语', '欧美', '日本', '韩国', '印度', '泰国', '其他'],
    ),
    DoubanCategory(
      type: 'tv',
      name: '剧集',
      collectionId: 'tv_real_time_hotest',
      genres: <String>[
        '全部', '剧情', '喜剧', '爱情', '悬疑', '犯罪', '科幻', '动画', '动作',
        '战争', '恐怖', '家庭', '古装', '武侠', '历史', '传记', '音乐', '真人秀', '脱口秀',
      ],
      years: _commonYears,
      platforms: <String>[
        '全部', 'Netflix', 'HBO', 'BBC', 'Hulu', 'Apple TV+', 'Disney+',
        'Amazon', 'YouTube', '腾讯视频', '爱奇艺', '优酷', '芒果TV', '央视',
      ],
      regions: <String>['全部', '华语', '欧美', '日本', '韩国', '其他'],
    ),
    DoubanCategory(
      type: 'variety',
      name: '综艺',
      collectionId: 'tv_variety_show',
      genres: <String>[
        '全部', '真人秀', '脱口秀', '音乐', '舞蹈', '美食', '旅行', '竞技',
        '访谈', '情感', '喜剧', '游戏', '文化', '职场',
      ],
      years: <String>[
        '全部', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019',
        '2018', '2017', '2010年代', '更早',
      ],
      platforms: <String>[
        '全部', '腾讯视频', '爱奇艺', '优酷', '芒果TV', '央视', 'Netflix', 'HBO',
        'BBC', 'Hulu', 'Apple TV+', 'Disney+', 'Amazon',
      ],
      regions: <String>['全部', '华语', '欧美', '日本', '韩国', '其他'],
    ),
    DoubanCategory(
      type: 'animation',
      name: '动漫',
      collectionId: 'tv_animation',
      genres: <String>[
        '全部', '剧情', '喜剧', '动作', '科幻', '奇幻', '冒险', '悬疑', '恐怖',
        '爱情', '家庭', '动画', '短片',
      ],
      years: _commonYears,
      platforms: <String>[
        '全部', 'Netflix', 'Crunchyroll', 'Bilibili', '腾讯视频', '爱奇艺',
        '优酷', 'Disney+', 'HBO', 'Hulu', 'Amazon', 'YouTube',
      ],
      regions: <String>['全部', '日本', '华语', '欧美', '韩国', '其他'],
    ),
    DoubanCategory(
      type: 'documentary',
      name: '纪录片',
      collectionId: 'movie_documentary',
      genres: <String>[
        '全部', '历史', '自然', '科学', '社会', '文化', '传记', '战争', '探险',
        '美食', '旅行', '音乐', '艺术', '体育',
      ],
      years: _commonYears,
      platforms: <String>[
        '全部', 'Netflix', 'BBC', 'Discovery', 'National Geographic', 'HBO',
        'Apple TV+', 'Disney+', 'Amazon', 'YouTube', '央视', 'Bilibili',
      ],
      regions: <String>['全部', '华语', '欧美', '日本', '韩国', '其他'],
    ),
  ];
}

/// 豆瓣排序方式。
enum DoubanSortType {
  hot,
  rating,
  year,
  latest;

  /// 展示名。
  String get displayName => switch (this) {
        DoubanSortType.hot => '热度',
        DoubanSortType.rating => '评分',
        DoubanSortType.year => '年份',
        DoubanSortType.latest => '最新',
      };
}

/// 豆瓣筛选参数。
class DoubanFilterParams {
  /// 构造。
  const DoubanFilterParams({
    this.genre,
    this.year,
    this.platform,
    this.region,
    this.sort = DoubanSortType.hot,
  });

  final String? genre;
  final String? year;
  final String? platform;
  final String? region;
  final DoubanSortType sort;

  /// 拷贝并覆盖。
  DoubanFilterParams copyWith({
    String? genre,
    String? year,
    String? platform,
    String? region,
    DoubanSortType? sort,
  }) =>
      DoubanFilterParams(
        genre: genre ?? this.genre,
        year: year ?? this.year,
        platform: platform ?? this.platform,
        region: region ?? this.region,
        sort: sort ?? this.sort,
      );
}

/// 首页区块。
class DoubanHomeSection {
  /// 构造。
  const DoubanHomeSection({required this.title, required this.items});

  final String title;
  final List<DoubanSubject> items;
}

/// 豆瓣首页聚合结果（banner + 区块）。
class DoubanHomeFeed {
  /// 构造。
  const DoubanHomeFeed({this.banner = const <DoubanSubject>[], this.sections = const <DoubanHomeSection>[]});

  /// 轮播横幅（TOP250 前若干）。
  final List<DoubanSubject> banner;

  /// 区块列表（仅保留非空区块）。
  final List<DoubanHomeSection> sections;

  /// 是否完全无内容。
  bool get isEmpty => banner.isEmpty && sections.isEmpty;
}