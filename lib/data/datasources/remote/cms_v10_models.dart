/// 数据层：CMS V10 接口模型与纯解析函数。
///
/// 逆向来源：iOS `vbox/Services/CMSV10Helper.swift` + `RemoteCMSV10Service.swift`
/// 接口形态（苹果 CMS V10）：
/// - 分类：`?ac=list`
/// - 列表：`?ac=videolist&pg=1&t=<type_id>&wd=<关键词>`（配 `at=json` 返回 JSON）
/// - 详情：`?ac=detail&ids=<vod_id>`
library;

import '../../../core/utils/json_utils.dart';

/// 分类。
class CmsV10Category {
  /// 构造。
  const CmsV10Category({
    required this.typeId,
    required this.typeName,
    this.typePid = 0,
  });

  /// 分类 ID。
  final String typeId;

  /// 分类名。
  final String typeName;

  /// 父分类 ID。
  final int typePid;

  /// 从 JSON 构造。
  factory CmsV10Category.fromJson(Map<String, Object?> j) => CmsV10Category(
        typeId: JsonUtils.pickStringOr(j, 'type_id', ''),
        typeName: JsonUtils.pickStringOr(j, 'type_name', ''),
        typePid: JsonUtils.pickInt(j, 'type_pid'),
      );

  @override
  String toString() => 'CmsV10Category($typeName/$typeId)';
}

/// 列表项 / 详情基础信息。
class CmsV10Video {
  /// 构造。
  const CmsV10Video({
    required this.vodId,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.year = '',
    this.area = '',
    this.typeName = '',
    this.playUrl = '',
  });

  /// 影片 ID。
  final String vodId;

  /// 名称。
  final String name;

  /// 封面（已归一为绝对地址）。
  final String pic;

  /// 备注（如「更新至 12 集」）。
  final String remarks;

  /// 年份。
  final String year;

  /// 地区。
  final String area;

  /// 分类名。
  final String typeName;

  /// 原始播放地址串（详情接口返回；格式见 [parseCmsPlayUrl]）。
  final String playUrl;

  /// 从 JSON 构造（封面按站点 host 归一）。
  factory CmsV10Video.fromJson(Map<String, Object?> j, String host) => CmsV10Video(
        vodId: JsonUtils.pickStringOr(j, 'vod_id', ''),
        name: JsonUtils.pickStringOr(j, 'vod_name', ''),
        pic: normalizeCmsPic(JsonUtils.pickStringOr(j, 'vod_pic', ''), host),
        remarks: JsonUtils.pickStringOr(j, 'vod_remarks', ''),
        year: JsonUtils.pickStringOr(j, 'vod_year', ''),
        area: JsonUtils.pickStringOr(j, 'vod_area', ''),
        typeName: JsonUtils.pickStringOr(j, 'type_name', ''),
        playUrl: JsonUtils.pickStringOr(j, 'vod_play_url', ''),
      );

  @override
  String toString() => 'CmsV10Video($name/$vodId)';
}

/// 剧集。
class CmsV10Episode {
  /// 构造。
  const CmsV10Episode({required this.name, required this.url});

  /// 集名（缺失时按序号生成）。
  final String name;

  /// 播放地址（已归一为绝对地址）。
  final String url;

  @override
  String toString() => 'CmsV10Episode($name → $url)';
}

/// 详情。
class CmsV10Detail {
  /// 构造。
  const CmsV10Detail({
    required this.video,
    this.episodes = const <CmsV10Episode>[],
    this.content = '',
    this.score = '',
    this.actors = '',
    this.director = '',
  });

  /// 基础信息。
  final CmsV10Video video;

  /// 剧集列表。
  final List<CmsV10Episode> episodes;

  /// 剧情简介（可能含 HTML）。
  final String content;

  /// 评分。
  final String score;

  /// 主演。
  final String actors;

  /// 导演。
  final String director;

  /// 从 JSON 构造。
  factory CmsV10Detail.fromJson(Map<String, Object?> j, String host) => CmsV10Detail(
        video: CmsV10Video.fromJson(j, host),
        episodes: parseCmsPlayUrl(JsonUtils.pickStringOr(j, 'vod_play_url', ''), host),
        content: JsonUtils.pickStringOr(j, 'vod_content', ''),
        score: JsonUtils.pickStringOr(j, 'vod_score', ''),
        actors: JsonUtils.pickStringOr(j, 'vod_actor', ''),
        director: JsonUtils.pickStringOr(j, 'vod_director', ''),
      );

  /// 是否可直接播放。
  bool get isPlayable => episodes.isNotEmpty;

  @override
  String toString() => 'CmsV10Detail(${video.name}, ${episodes.length} 集)';
}

// ─────────────────────────────────────────────────────────
// 纯解析函数（无 IO，可单测）
// ─────────────────────────────────────────────────────────

/// 播放地址归一（对齐 iOS `CMSV10Helper.normalizeUrl`）。
///
/// 规则：
/// - 已含 `http://` / `https://` → 原样；
/// - `//host/x` → 补 `https:`；
/// - `/path` → 拼站点 host；
/// - 其他 → 补 `https://` 前缀。
///
/// ⚠️ 与 iOS 的差异：iOS 对 `/path` 直接拼 `https://`（会得到 `https:///path`），
/// 此处改为拼站点 host（更正确，属**有意的行为改进**，已在方案文档登记）。
String normalizeCmsUrl(String url, String host) {
  final String u = url.trim();
  if (u.isEmpty) return '';
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  if (u.startsWith('//')) return 'https:$u';
  if (u.startsWith('/')) return host.isEmpty ? u : 'https://$host$u';
  if (u.contains('://')) return u;
  return 'https://$u';
}

/// 封面归一（对齐 iOS `CMSV10Helper.normalizePic`）。
String normalizeCmsPic(String pic, String host) => normalizeCmsUrl(pic, host);

/// 解析 `vod_play_url` 为剧集列表。
///
/// 契约格式：`名称$地址#名称$地址#…`（苹果 CMS V10 标准）。
/// - 无 `$` 时按序号生成集名；
/// - 空地址条目跳过；
/// - 地址按 [host] 归一。
List<CmsV10Episode> parseCmsPlayUrl(String raw, String host) {
  final String s = raw.trim();
  if (s.isEmpty) return const <CmsV10Episode>[];
  final List<CmsV10Episode> out = <CmsV10Episode>[];
  final List<String> segments = s.split('#');
  for (int i = 0; i < segments.length; i++) {
    final String seg = segments[i].trim();
    if (seg.isEmpty) continue;
    final int sep = seg.indexOf(r'$');
    final String name = sep >= 0 ? seg.substring(0, sep).trim() : '第${i + 1}集';
    final String rawUrl = sep >= 0 ? seg.substring(sep + 1).trim() : seg;
    final String url = normalizeCmsUrl(rawUrl, host);
    if (url.isEmpty) continue;
    out.add(CmsV10Episode(name: name.isEmpty ? '第${i + 1}集' : name, url: url));
  }
  return out;
}
