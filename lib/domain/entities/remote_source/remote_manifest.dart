/// 领域层：远程源 manifest 模型。
///
/// 唯一真相源：`contract/schema/manifest_v1.json`
/// 逆向来源：iOS `vbox/Services/RemoteSourceConfigManager.swift`
library;

/// 远程源 manifest（对齐契约 manifest_v1.json）。
class RemoteManifest {
  const RemoteManifest({
    this.schemaVersion = 1,
    required this.configVersion,
    this.minAppVersion,
    this.updatedAt,
    this.ttlSeconds = defaultTtlSeconds,
    this.forceRefresh = true,
    this.disabledKeys = const <String>[],
    required this.files,
    this.meta,
  });

  /// 缓存有效期默认值（契约实测 21600 = 6 小时）。
  static const int defaultTtlSeconds = 21600;

  /// manifest 结构版本，契约固定为 1。
  final int schemaVersion;

  /// 配置版本号，格式 `YYYY.MM.DD.N`。
  final String configVersion;

  /// 客户端最低版本要求（兼容门控）。
  final String? minAppVersion;

  /// 更新时间（ISO 8601 UTC）。
  final String? updatedAt;

  /// 缓存有效期（秒）。
  final int ttlSeconds;

  /// 是否强制全量刷新。
  final bool forceRefresh;

  /// 全局禁用的源 key 列表。
  final List<String> disabledKeys;

  /// 各配置文件地址（10 个键，实测）。
  final Map<String, String> files;

  /// 自描述元信息（`_meta`）。
  final Map<String, Object?>? meta;

  /// 契约要求的 `configVersion` 格式：`YYYY.MM.DD.N`。
  static final RegExp configVersionPattern =
      RegExp(r'^\d{4}\.\d{2}\.\d{2}\.\d+$');

  /// configVersion 是否符合契约格式。
  bool get hasValidConfigVersion =>
      configVersionPattern.hasMatch(configVersion);

  /// 必需文件键（契约 `files.required`）。
  static const String keyAllSources = 'allSources';

  /// 已知文件键（契约，10 个）。
  static const List<String> knownFileKeys = <String>[
    'allSources',
    'apiSources',
    'cloudSources',
    'spiderSources',
    'domainOverrides',
    'parsers',
    'disabledSources',
    'welfarePlatforms',
    'nodeRuntimeBundle',
    'nodeRuntimeBundleVer',
  ];

  /// 是否包含必需键 allSources。
  bool get hasRequiredFiles => files.containsKey(keyAllSources);

  factory RemoteManifest.fromJson(Map<String, Object?> j) => RemoteManifest(
        schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
        configVersion: (j['configVersion'] ?? '').toString(),
        minAppVersion: j['minAppVersion']?.toString(),
        updatedAt: j['updatedAt']?.toString(),
        ttlSeconds:
            (j['ttlSeconds'] as num?)?.toInt() ?? defaultTtlSeconds,
        forceRefresh: j['forceRefresh'] as bool? ?? true,
        disabledKeys: (j['disabledKeys'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
        files: (j['files'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString())) ??
            const <String, String>{},
        meta: (j['_meta'] as Map?)?.cast<String, Object?>(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        if (meta != null) '_meta': meta,
        'schemaVersion': schemaVersion,
        'configVersion': configVersion,
        if (minAppVersion != null) 'minAppVersion': minAppVersion,
        if (updatedAt != null) 'updatedAt': updatedAt,
        'ttlSeconds': ttlSeconds,
        'forceRefresh': forceRefresh,
        'disabledKeys': disabledKeys,
        'files': files,
      };
}

/// all_sources.json 聚合容器（契约 `$defs.allSources`，实测 7 键）。
class AllSourcesContainer {
  const AllSourcesContainer({
    this.apiSources,
    this.cloudSources,
    this.spiderSources,
    this.domainOverrides,
    this.parsers,
    this.disabledSources,
    this.welfarePlatforms,
  });

  final Map<String, Object?>? apiSources;
  final Map<String, Object?>? cloudSources;
  final Map<String, Object?>? spiderSources;
  final Map<String, Object?>? domainOverrides;
  final List<Object?>? parsers;
  final List<Object?>? disabledSources;
  final Map<String, Object?>? welfarePlatforms;

  factory AllSourcesContainer.fromJson(Map<String, Object?> j) =>
      AllSourcesContainer(
        apiSources: (j['apiSources'] as Map?)?.cast<String, Object?>(),
        cloudSources: (j['cloudSources'] as Map?)?.cast<String, Object?>(),
        spiderSources: (j['spiderSources'] as Map?)?.cast<String, Object?>(),
        domainOverrides: (j['domainOverrides'] as Map?)?.cast<String, Object?>(),
        parsers: (j['parsers'] as List?)?.cast<Object?>(),
        disabledSources: (j['disabledSources'] as List?)?.cast<Object?>(),
        welfarePlatforms:
            (j['welfarePlatforms'] as Map?)?.cast<String, Object?>(),
      );

  /// 聚合出的站点列表（apiSources.sites + spiderSources.sites）。
  List<Map<String, Object?>> get sites {
    final List<Map<String, Object?>> out = <Map<String, Object?>>[];
    void collect(Map<String, Object?>? src) {
      final Object? arr = src?['sites'];
      if (arr is List) {
        for (final Object? e in arr) {
          if (e is Map) out.add(e.cast<String, Object?>());
        }
      }
    }

    collect(apiSources);
    collect(spiderSources);
    return out;
  }
}
