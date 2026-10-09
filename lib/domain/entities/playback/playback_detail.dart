/// 领域层：详情页·播放入口模型（Spider 内容 → 可播放剧集）。
///
/// 唯一真相源：`contract/docs/abi_v1.md` §3「返回结构」的
/// `vod_play_from` / `vod_play_url` 解析规则（`$$$` 分隔线路、`#` 分隔剧集、`$` 分隔名/地址），
/// 示例见契约 §3.4：`"线路1$$$线路2"` + `"第1集$url1#第2集$url2$$$第1集$url3"`。
library;

import '../cloud/cloud_drive.dart';
import '../cloud/node_pan.dart';
import '../spider/site_config.dart';
import '../spider/spider_models.dart';

/// 剧集资源类型（对齐 iOS `EpisodeItem.EpisodeSourceType`，11 档）。
///
/// 切集时用于选择对应播放逻辑；`rawValue` 与 iOS 一致。
enum EpisodeSourceType {
  /// 普通资源（蜘蛛直链）。
  normal('normal'),

  /// 百度网盘（原生）。
  baidu('baidu'),

  /// 夸克网盘（原生）。
  quark('quark'),

  /// 迅雷云盘。
  xunlei('xunlei'),

  /// 阿里云盘。
  ali('ali'),

  /// 115 网盘。
  one15('one15'),

  /// 123 云盘。
  pan123('pan123'),

  /// 139 云盘。
  pan139('pan139'),

  /// 天翼云盘（189）。
  pan189('pan189'),

  /// 其他网盘（UC 等）。
  drive('drive'),

  /// Node 托管网盘（115/123/139/189/迅雷/光鸭/蜗牛/夸克Node/UCNode/百度Node）。
  node('node');

  const EpisodeSourceType(this.value);

  /// 契约字符串值（对齐 iOS `rawValue`）。
  final String value;

  /// 由网盘类型映射资源类型（对齐 iOS 各 `handleDriveUrl` 分支的 `sourceType`）。
  ///
  /// Node 托管盘一律归 [node]（iOS 可达路径经 `handleNodeManagedDrive`）；
  /// 原生盘按盘别映射；非网盘（null）归 [normal]。
  static EpisodeSourceType fromDriveType(CloudDriveType? type) {
    if (type == null) return EpisodeSourceType.normal;
    if (NodePanRouting.isNodeManaged(type)) return EpisodeSourceType.node;
    return switch (type) {
      CloudDriveType.ali => EpisodeSourceType.ali,
      CloudDriveType.quark => EpisodeSourceType.quark,
      CloudDriveType.baidu => EpisodeSourceType.baidu,
      // UC 原生在 iOS 归 `.drive`（无独立档）。
      _ => EpisodeSourceType.drive,
    };
  }
}

/// 单集可播放项。
class PlaybackEpisode {
  /// 构造。
  const PlaybackEpisode({
    required this.name,
    required this.url,
    this.from,
    this.fileId = '',
    this.sourceType = EpisodeSourceType.normal,
    this.nodePlayID,
    this.nodeDriveType,
  });

  /// 剧集名（如「第 1 集」，解析失败时可能为空串）。
  final String name;

  /// 播放地址（直链或需二次解析的页面地址）。
  final String url;

  /// 所属线路（`vod_play_from` 对应项；未知为 null）。
  final String? from;

  /// 网盘文件 ID（分享 / 文件列表选集定位用；非网盘源为空串）。
  ///
  /// F-P06 网盘字段扩展的首批落地字段 —— 仅供「分享内多文件选集」定位使用；
  /// 其余网盘字段（各盘 fileIndex / headers 等）随第 4 批网盘链路补入。
  final String fileId;

  /// 资源类型（对齐 iOS `EpisodeItem.sourceType`）：切集时选择对应播放逻辑。
  final EpisodeSourceType sourceType;

  /// Node 托管盘 playID（对齐 iOS `EpisodeItem.nodePlayID`）—— 切集取链时
  /// 交给 `/spider/push/4/play`；非 Node 源为 null。
  final String? nodePlayID;

  /// Node 托管盘类型（对齐 iOS `EpisodeItem.nodeDriveType`）—— 切集取链时
  /// 用于映射盘别；非 Node 源为 null。
  final CloudDriveType? nodeDriveType;

  /// 是否直链媒体（无需 playerContent 二次解析）。
  bool get isDirectMedia => PlaybackUrlParser.looksDirectMedia(url);

  @override
  String toString() => 'PlaybackEpisode(${name.isEmpty ? '(未命名)' : name})';
}

/// 详情播放页数据（站点 + 详情 + 剧集列表）。
class PlaybackDetail {
  /// 构造。
  const PlaybackDetail({
    required this.site,
    required this.vod,
    required this.froms,
    required this.episodes,
    this.initialIndex = 0,
  });

  /// 站点配置（供引擎重建 / playerContent 解析）。
  final SiteConfig site;

  /// 详情条目。
  final VodItem vod;

  /// 线路名列表（`vod_play_from` 拆分，可为空）。
  final List<String> froms;

  /// 剧集列表（已过滤空地址）。
  final List<PlaybackEpisode> episodes;

  /// 默认选中的剧集索引（收藏/历史续播入口传入）。
  final int initialIndex;

  /// 由详情条目构建（解析 `vod_play_from` / `vod_play_url`）。
  ///
  /// [initialIndex] 会被钳制到合法区间。
  factory PlaybackDetail.fromVod({
    required SiteConfig site,
    required VodItem vod,
    int initialIndex = 0,
  }) {
    final ParsedPlayUrl parsed =
        PlaybackUrlParser.parse(vod.vodPlayFrom, vod.vodPlayUrl);
    final int clamped = initialIndex < 0 || parsed.episodes.isEmpty
        ? 0
        : initialIndex >= parsed.episodes.length
            ? parsed.episodes.length - 1
            : initialIndex;
    return PlaybackDetail(
      site: site,
      vod: vod,
      froms: parsed.froms,
      episodes: parsed.episodes,
      initialIndex: clamped,
    );
  }
}

/// `vod_play_from` / `vod_play_url` 解析结果。
class ParsedPlayUrl {
  /// 构造。
  const ParsedPlayUrl({required this.froms, required this.episodes});

  /// 线路名列表。
  final List<String> froms;

  /// 剧集列表。
  final List<PlaybackEpisode> episodes;
}

/// TVBox `vod_play_url` 解析器（契约 §3）。
///
/// 格式（契约 §3.4 示例）：
/// ```
/// vod_play_from: "线路1$$$线路2"
/// vod_play_url:  "第1集$url1#第2集$url2$$$第1集$url3"
/// ```
/// 规则：
/// - `$$$` 分隔线路；每线路内 `#` 分隔剧集；每剧集 `name$url`（地址可能含 `$`，取首个 `$` 之后剩余拼接）；
/// - 空地址剧集被过滤；`from` 缺失时以线路序号回填；
/// - 容错：任一字段缺失/格式非法 → 空结果，不抛异常。
class PlaybackUrlParser {
  PlaybackUrlParser._();

  /// 线路分隔符（契约 §3.4）。
  static const String sourceSeparator = r'$$$';

  /// 剧集分隔符。
  static const String episodeSeparator = '#';

  /// 名称/地址分隔符。
  static const String nameUrlSeparator = r'$';

  /// 直链媒体扩展名清单（命中即免二次解析）。
  static const List<String> directMediaExtensions = <String>[
    '.m3u8', '.mp4', '.m4v', '.webm', '.mkv', '.flv', '.ts',
    '.avi', '.rmvb', '.wmv', '.mov', '.mpd',
    '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.oga', '.opus',
  ];

  /// 解析 `vod_play_from` / `vod_play_url`。
  static ParsedPlayUrl parse(String? fromRaw, String? urlRaw) {
    final String url = (urlRaw ?? '').trim();
    if (url.isEmpty) return const ParsedPlayUrl(froms: <String>[], episodes: <PlaybackEpisode>[]);

    final List<String> froms = _splitSources(fromRaw ?? '')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    final List<String> sources = _splitSources(url);
    final List<PlaybackEpisode> episodes = <PlaybackEpisode>[];

    for (int i = 0; i < sources.length; i++) {
      final String from = i < froms.length ? froms[i] : '线路${i + 1}';
      for (final String seg in sources[i].split(episodeSeparator)) {
        final String raw = seg.trim();
        if (raw.isEmpty) continue;
        final int splitAt = raw.indexOf(nameUrlSeparator);
        if (splitAt < 0) continue; // 无「$」分隔 → 非法剧集段
        final String name = raw.substring(0, splitAt).trim();
        final String playUrl = raw.substring(splitAt + 1).trim();
        if (playUrl.isEmpty) continue;
        episodes.add(PlaybackEpisode(name: name, url: playUrl, from: from));
      }
    }
    return ParsedPlayUrl(froms: froms, episodes: episodes);
  }

  /// 判断地址是否为直链媒体（http/https + 命中媒体扩展名）。
  static bool looksDirectMedia(String url) {
    final String u = url.trim().toLowerCase();
    if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
    for (final String ext in directMediaExtensions) {
      if (u.contains(ext)) return true;
    }
    return false;
  }

  /// 按 `$$$` 拆分（`$$$` 亦兼容 `$$` 残余写法）。
  static List<String> _splitSources(String raw) {
    final List<String> parts = raw.split(sourceSeparator);
    final List<String> out = <String>[];
    for (final String p in parts) {
      // 兼容部分源用 `$$` 分隔线路（`$$$` 拆分后的残余片段再按 `$$` 拆）
      out.addAll(p.split(r'$$').where((String s) => s.isNotEmpty));
    }
    return out;
  }
}
