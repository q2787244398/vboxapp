/// 数据层：备份采集（dump）/ 还原（restore）服务。
///
/// 唯一真相源：`contract/docs/backup_v1.md`
///   - §3 9 个类目 · §5 Payload 结构 · §7 个人设置白名单 · §8 冲突策略
///
/// 职责：把本机数据（SQLite 表 + 契约 Prefs 键 + 远程源缓存）采集为
/// [BackupPayload]；以及把 [BackupPayload] 按冲突策略写回本机。
/// 加解密与信封编解码由 [BackupManager] 负责，本文件不碰密码学。
///
/// 类目 ↔ 数据源映射：
/// | 类目 | 数据源 |
/// |------|--------|
/// | watchHistory | `history` 表 |
/// | favorites | `favorite` 表 |
/// | downloads | `download` 表 |
/// | subscriptions | `subscription` 表 |
/// | siteConfigs | `zhanyuan` + `apiyuan` + `jiexisetting` 表 |
/// | personalSettings | 契约 Prefs 白名单（14 键，福利 3 键仅加密时） |
/// | remoteSources | manifest 缓存（`cache/remote_manifest.json`） |
/// | searchHistory | `search_history` 表 |
/// | cloudCredentials | 契约 Prefs 云盘凭据键（安全存储） |
///
/// ⚠️ 冲突策略（契约 §8）：
/// - [ConflictStrategy.merge]：不删除本机数据，逐行按主键 `replace`（本机独有保留）
/// - [ConflictStrategy.overwrite]：先清空该类目，再整体写入
library;

import 'dart:convert';
import 'dart:io';

import '../../../contract/prefs_keys.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/storage/file_store.dart';
import '../../../core/storage/storage_paths.dart';
import 'backup_manager.dart';
import 'backup_payload.dart';
import 'database_manager.dart';
import 'prefs_manager.dart';

/// 类目 → SQLite 表（仅「表直映」类目；其余见 [BackupService] 文档）。
const Map<BackupCategory, List<String>> kCategoryTables =
    <BackupCategory, List<String>>{
  BackupCategory.watchHistory: <String>['history'],
  BackupCategory.favorites: <String>['favorite'],
  BackupCategory.downloads: <String>['download'],
  BackupCategory.subscriptions: <String>['subscription'],
  BackupCategory.searchHistory: <String>['search_history'],
};

/// `siteConfigs` 类目下的三张表（对齐 `SiteConfigsSnapshot`）。
const List<String> kSiteConfigTables = <String>[
  'zhanyuan',
  'apiyuan',
  'jiexisetting',
];

/// 个人设置白名单前 11 键（常态备份，契约 §7）。
const List<String> kPersonalSettingKeys = <String>[
  'app_skin_mode',
  'app_skin_follows_system',
  'app_enable_tmdb',
  'app_tmdb_proxy_url',
  'app_tmdb_use_token',
  'app_tmdb_proxy_token',
  'app_dev_log_enabled',
  'app_dev_log_level',
  'remote_default_source_enabled',
  'bundle_sources_enabled',
  'remote_default_manifest_url',
];

/// 福利白名单 3 键（**仅加密备份时**采集与还原，契约 §7）。
const List<String> kWelfareSettingKeys = <String>[
  'app_welfare_unlocked',
  'app_welfare_password',
  'app_welfare_enabled',
];

/// 网盘凭据相关的契约键（`cloudCredentials` 类目）。
const List<String> kCloudCredentialKeys = <String>[
  'cloud_drive_credentials_v1',
  'saved_drive_tokens_v1',
  'saved_drive_tokens',
];

/// 备份文件信息（UI 列表展示用）。
class BackupFileInfo {
  const BackupFileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
}

/// 还原结果报告。
class BackupRestoreReport {
  const BackupRestoreReport({
    required this.strategy,
    required this.counts,
    required this.missing,
  });

  final ConflictStrategy strategy;

  /// 各类目实际写入条数（表类目为行数；设置类目为键数）。
  final Map<BackupCategory, int> counts;

  /// 备份中无该类目数据（跳过）。
  final Set<BackupCategory> missing;

  int get total => counts.values.fold(0, (int a, int b) => a + b);
}

/// 备份采集 / 还原服务。
class BackupService {
  /// 构造（[db] / [prefs] 便于单测注入）。
  BackupService({DatabaseManager? db, PrefsManager? prefs})
      : _db = db ?? DatabaseManager.instance,
        _prefs = prefs ?? PrefsManager.instance;

  final DatabaseManager _db;
  final PrefsManager _prefs;

  /// 远程源清单缓存路径。
  static String get _manifestCachePath =>
      FileStore.join(StoragePaths.cacheDir, 'remote_manifest.json');

  // ─────────────────────────────────────────────────────────
  // 采集（dump）
  // ─────────────────────────────────────────────────────────

  /// 采集指定类目，产出一个 [BackupPayload]。
  ///
  /// [includeWelfare]：是否采集福利 3 键（**仅加密备份时为 true**，契约 §7）。
  /// [account]：写入 payload 的账号标识。
  Future<BackupPayload> dump({
    required Set<BackupCategory> categories,
    bool includeWelfare = false,
    String account = '',
  }) async {
    final BackupPayload payload = BackupPayload(account: account);

    for (final BackupCategory c in categories) {
      switch (c) {
        case BackupCategory.watchHistory:
        case BackupCategory.favorites:
        case BackupCategory.downloads:
        case BackupCategory.subscriptions:
        case BackupCategory.searchHistory:
          final List<Map<String, Object?>> rows =
              await _db.queryAll(kCategoryTables[c]!.first);
          payload.putCategory(c, rows);
        case BackupCategory.siteConfigs:
          payload.putCategory(c, await _dumpSiteConfigs());
        case BackupCategory.personalSettings:
          payload.putCategory(c, await _dumpPersonalSettings(includeWelfare));
        case BackupCategory.remoteSources:
          payload.putCategory(c, await _dumpRemoteSources());
        case BackupCategory.cloudCredentials:
          payload.putCategory(c, await _dumpCredentials());
      }
    }
    return payload;
  }

  Future<Map<String, Object?>> _dumpSiteConfigs() async {
    final Map<String, Object?> out = <String, Object?>{};
    for (final String t in kSiteConfigTables) {
      out[_siteKey(t)] = await _db.queryAll(t);
    }
    return out;
  }

  /// 表名 → `SiteConfigsSnapshot` 键（jiexisetting → jiexi）。
  static String _siteKey(String table) =>
      table == 'jiexisetting' ? 'jiexi' : table;

  Future<Map<String, Object?>> _dumpPersonalSettings(bool includeWelfare) async {
    final List<String> keys = <String>[
      ...kPersonalSettingKeys,
      if (includeWelfare) ...kWelfareSettingKeys,
    ];
    final Map<String, String> defaults = <String, String>{};
    for (final String k in keys) {
      defaults[k] = _stringifyPref(await _prefs.get(k));
    }
    return <String, Object?>{
      'username': '',
      'avatarBase64': null,
      'defaults': defaults,
    };
  }

  Future<Map<String, Object?>> _dumpRemoteSources() async {
    String version = '';
    Object? manifest;
    try {
      version = await _prefs.getString('remote_default_last_config_version');
      final Map<String, Object?>? box =
          await FileStore.readJsonMap(_manifestCachePath);
      final Object? raw = box?['manifest'];
      // 契约用 `Data?` → Base64 字符串承载 manifest JSON。
      if (raw != null) {
        manifest = base64.encode(utf8.encode(jsonEncode(raw)));
      }
    } catch (_) {
      // 缓存读失败 → 空快照（不阻断备份）
    }
    return <String, Object?>{
      'version': version,
      'manifest': manifest,
      'allSources': null,
      'spiderJS': <String, Object?>{},
      'lxPlugins': <String, Object?>{},
    };
  }

  Future<Map<String, Object?>> _dumpCredentials() async {
    final Map<String, Object?> credentials = <String, Object?>{};
    for (final String k in kCloudCredentialKeys) {
      final Object? v = await _prefs.get(k);
      if (v == null || '$v'.isEmpty) continue;
      // 若本身是 JSON 对象则原样内嵌，否则以字符串承载（本机无非结构化凭据模型）。
      credentials[k] = _tryDecodeJson('$v') ?? '$v';
    }
    return <String, Object?>{'credentials': credentials, 'tokens': <Object?>[]};
  }

  // ─────────────────────────────────────────────────────────
  // 还原（restore）
  // ─────────────────────────────────────────────────────────

  /// 把 [payload] 中指定类目写回本机。
  Future<BackupRestoreReport> restore({
    required BackupPayload payload,
    required Set<BackupCategory> categories,
    required ConflictStrategy strategy,
  }) async {
    final Map<BackupCategory, int> counts = <BackupCategory, int>{};
    final Set<BackupCategory> missing = <BackupCategory>{};

    for (final BackupCategory c in categories) {
      final Object? data = payload.readCategory(c);
      if (data == null) {
        missing.add(c);
        continue;
      }
      counts[c] = await _restoreCategory(c, data, strategy);
    }
    return BackupRestoreReport(
      strategy: strategy,
      counts: counts,
      missing: missing,
    );
  }

  Future<int> _restoreCategory(
    BackupCategory c,
    Object? data,
    ConflictStrategy strategy,
  ) async {
    switch (c) {
      case BackupCategory.watchHistory:
      case BackupCategory.favorites:
      case BackupCategory.downloads:
      case BackupCategory.subscriptions:
      case BackupCategory.searchHistory:
        return _restoreTable(kCategoryTables[c]!.first, data, strategy);
      case BackupCategory.siteConfigs:
        final Map<String, Object?> snap =
            (data as Map).cast<String, Object?>();
        int n = 0;
        for (final String t in kSiteConfigTables) {
          n += await _restoreTable(
              t, snap[_siteKey(t)] ?? const <Object?>[], strategy);
        }
        return n;
      case BackupCategory.personalSettings:
        return _restorePersonalSettings(
            (data as Map).cast<String, Object?>(), strategy);
      case BackupCategory.remoteSources:
        return _restoreRemoteSources((data as Map).cast<String, Object?>());
      case BackupCategory.cloudCredentials:
        return _restoreCredentials(
            (data as Map).cast<String, Object?>(), strategy);
    }
  }

  Future<int> _restoreTable(
    String table,
    Object? data,
    ConflictStrategy strategy,
  ) async {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    if (data is List) {
      for (final Object? row in data) {
        if (row is Map) rows.add(row.cast<String, Object?>());
      }
    }
    if (strategy == ConflictStrategy.overwrite) {
      await _db.delete(table, where: '1 = 1', whereArgs: const <Object?>[]);
    }
    for (final Map<String, Object?> row in rows) {
      await _db.upsert(table, row, primaryKey: 'id');
    }
    return rows.length;
  }

  Future<int> _restorePersonalSettings(
    Map<String, Object?> snap,
    ConflictStrategy strategy,
  ) async {
    final Object? rawDefaults = snap['defaults'];
    if (rawDefaults is! Map) return 0;
    final List<String> whitelist = <String>[
      ...kPersonalSettingKeys,
      ...kWelfareSettingKeys,
    ];
    int n = 0;
    for (final String k in whitelist) {
      final Object? raw = rawDefaults[k];
      if (raw == null) continue;
      final String value = '$raw';
      final PrefsKey? meta = findPrefsKey(k);
      if (meta == null) continue;

      if (strategy == ConflictStrategy.merge) {
        // 合并：仅补齐本机缺失/空值，不覆盖本机已有设置。
        final Object? local = await _prefs.get(k);
        if (local != null && _stringifyPref(local).isNotEmpty) continue;
      }
      await _prefs.set(k, _coercePref(meta.type, value));
      n++;
    }
    return n;
  }

  Future<int> _restoreRemoteSources(Map<String, Object?> snap) async {
    final Object? manifestB64 = snap['manifest'];
    if (manifestB64 is! String || manifestB64.isEmpty) return 0;
    try {
      final Object? manifestJson =
          jsonDecode(utf8.decode(base64.decode(manifestB64)));
      await FileStore.writeJson(_manifestCachePath, <String, Object?>{
        'cachedAtSeconds':
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'manifest': manifestJson,
      });
      final Object? version = snap['version'];
      if (version is String && version.isNotEmpty) {
        await _prefs.set('remote_default_last_config_version', version);
      }
      return 1;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _restoreCredentials(
    Map<String, Object?> snap,
    ConflictStrategy strategy,
  ) async {
    final Object? rawCreds = snap['credentials'];
    if (rawCreds is! Map) return 0;
    int n = 0;
    for (final String k in kCloudCredentialKeys) {
      final Object? v = rawCreds[k];
      if (v == null) continue;
      if (strategy == ConflictStrategy.merge) {
        final Object? local = await _prefs.get(k);
        if (local != null && '$local'.isNotEmpty) continue;
      }
      final String stored = v is String ? v : jsonEncode(v);
      await _prefs.set(k, stored);
      n++;
    }
    return n;
  }

  // ─────────────────────────────────────────────────────────
  // 备份文件 I/O（统一扩展名 `.vboxbak`）
  // ─────────────────────────────────────────────────────────

  /// 生成备份文件名（`vbox_backup_yyyyMMdd_HHmmss.vboxbak`）。
  static String buildFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final String stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${DbConstants.backupFilePrefix}$stamp'
        '${DbConstants.backupFileExtension}';
  }

  /// 把信封内容写入备份目录，返回文件绝对路径。
  Future<String> writeBackupFile(String content, {DateTime? now}) async {
    final String name = buildFileName(now ?? DateTime.now());
    final String path = FileStore.join(StoragePaths.backupDir, name);
    await FileStore.writeString(path, content);
    return path;
  }

  /// 列出备份目录下的 `.vboxbak` 文件（按修改时间倒序）。
  Future<List<BackupFileInfo>> listBackupFiles() async {
    final List<String> paths = await FileStore.list(
      StoragePaths.backupDir,
      suffix: DbConstants.backupFileExtension,
    );
    final List<BackupFileInfo> out = <BackupFileInfo>[];
    for (final String p in paths) {
      final File f = File(p);
      out.add(BackupFileInfo(
        path: p,
        name: f.uri.pathSegments.last,
        sizeBytes: await FileStore.sizeOf(p),
        modifiedAt: await f.exists() ? await f.lastModified() : DateTime(0),
      ));
    }
    out.sort((BackupFileInfo a, BackupFileInfo b) =>
        b.modifiedAt.compareTo(a.modifiedAt));
    return out;
  }

  /// 读取备份文件内容。
  Future<String> readBackupFile(String path) async {
    final String? text = await FileStore.readString(path);
    if (text == null) {
      throw const InvalidFormatException('备份文件不存在或不可读');
    }
    return text;
  }

  /// 删除备份文件。
  Future<bool> deleteBackupFile(String path) => FileStore.delete(path);

  // ─────────────────────────────────────────────────────────
  // 内部工具
  // ─────────────────────────────────────────────────────────

  /// 把 Prefs 值统一序列化为字符串（对齐 `defaults: [String: String]`）。
  static String _stringifyPref(Object? v) {
    if (v == null) return '';
    if (v is bool) return v ? 'true' : 'false';
    if (v is List) return jsonEncode(v);
    return '$v';
  }

  /// 按契约 type 把字符串还原为原生类型（供 [PrefsManager.set] 使用）。
  static Object? _coercePref(PrefsType type, String raw) => switch (type) {
        PrefsType.bool => raw == 'true' || raw == '1',
        PrefsType.int || PrefsType.long => int.tryParse(raw) ?? 0,
        PrefsType.float => double.tryParse(raw) ?? 0.0,
        PrefsType.string => raw,
        PrefsType.stringArray => _decodeStringList(raw),
      };

  static List<String> _decodeStringList(String raw) {
    try {
      final Object? d = jsonDecode(raw);
      return d is List ? d.map((Object? e) => '$e').toList() : <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  static Object? _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// 构造备份元数据（`appVersion` 取当前版本）。
  static BackupMeta buildMeta({String account = ''}) => BackupMeta(
        appName: AppInfo.displayName,
        appVersion: AppInfo.version,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        account: account,
        username: '',
        device: Platform.operatingSystem,
      );
}