/// 数据层：远程源配置管理器（第 2 轮批次 B · B-01 / B-02 / B-03）。
///
/// 唯一真相源：iOS `vbox/Services/RemoteSourceConfigManager.swift`
///   - `syncIfNeeded(force:)`（L95-146）：开关 → 空地址 → 从未同步 → App 升级 →
///     force → 版本探测（未变不进全量）→ 降级 TTL 的状态机；
///   - `syncNow()`（L148-208）：manifest 校验 → allSources → 缓存落盘 →
///     Node bundle 键镜像；
///   - `checkManifestVersion()`（L216-237）：`/manifest.version`（约 30 字节）
///     轻量探测；`manifest.json` → `manifest.version` / `<url>.version` 两种派生；
///   - `fetchData` / `buildProxyURLs` / `isGitHubDomain`（L728-768）：
///     仅 GitHub 域名走代理降级链（主代理 → 备用代理 → 直连）；
///   - `shouldRefresh()`（L772-777）：TTL 过期或清单自带 `forceRefresh`。
///
/// 与既有分层的分工：
/// - 单次拉取/校验 → `RemoteManifestDatasource` / `AllSourcesDatasource`；
/// - 缓存清单落盘/读取 → `RemoteSourceRepository`（文件缓存 + 契约镜像键）；
/// - 本管理器只做**编排**：契约同步键（`remote_default_*` 9 键）状态机 +
///   版本探测 + 兼容门控（`minAppVersion`）+ 6 合 1 聚合解析。
///
/// 时间 / App 版本由调用方注入（单测确定性）；时间基准为 Unix 秒。
library;

import '../../../contract/prefs_keys.dart' show findPrefsKey;
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/json_utils.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/remote_source/remote_source.dart';
import '../../../domain/repositories/remote_source_repository.dart';
import '../local/prefs_manager.dart';
import 'all_sources_datasource.dart';
import 'remote_manifest_datasource.dart';

/// 同步动作（状态机出口，对齐 iOS `syncIfNeeded` 各分支）。
enum RemoteSourceSyncAction {
  /// 远程默认源开关关闭 → 跳过网络同步，仅加载缓存。
  skippedDisabled,

  /// manifest 地址留空 → 跳过网络同步，仅加载缓存（消除必然失败的联网请求）。
  skippedEmptyUrl,

  /// 调用方强制刷新。
  forceRefresh,

  /// App 版本变化 → 强制全量同步。
  appVersionChanged,

  /// 从未同步过（lastSyncTime 为空）→ 全量同步。
  firstSync,

  /// 版本探测成功且 `configVersion` 变化 → 全量同步。
  versionChanged,

  /// 版本探测成功且版本一致 → **跳过全量拉取**（B-01 核心验收）。
  versionUnchanged,

  /// 版本探测失败 → 降级 TTL 判定，缓存已过期 → 全量同步。
  probeFailedTtlExpired,

  /// 版本探测失败 → 降级 TTL 判定，缓存未过期 → 用缓存。
  probeFailedUpToDate,

  /// 全量同步成功。
  synced,

  /// manifest 最低版本要求高于当前 App 版本 → 拒绝同步（兼容门控）。
  incompatibleMinAppVersion,

  /// 全量同步失败（失败原因已写入 `remote_default_last_sync_error`）。
  syncFailed,
}

/// `syncIfNeeded` / `syncNow` 的编排结果。
class RemoteSourceSyncResult {
  const RemoteSourceSyncResult({
    required this.action,
    required this.status,
    this.manifest,
    this.sites = const <Map<String, Object?>>[],
    this.error,
    this.fullSync = false,
  });

  /// 触发的状态机分支（成功时保留触发原因，失败时为 syncFailed / 门控分支）。
  final RemoteSourceSyncAction action;

  /// 加载状态（供 UI 展示，对齐 iOS `LoadState`）。
  final RemoteLoadStatus status;

  /// 当前生效清单（远程或缓存；两者皆无时为 null）。
  final RemoteManifest? manifest;

  /// 6 合 1 聚合站点（仅全量同步成功时非空）。
  final List<Map<String, Object?>> sites;

  /// 失败原因（syncFailed / incompatibleMinAppVersion 时有值）。
  final String? error;

  /// 本次是否执行了全量同步并成功（独立于 [action] 的触发原因）。
  final bool fullSync;

  /// 本次是否执行了全量同步并成功。
  bool get didFullSync => fullSync;
}

/// 远程源配置管理器（编排器，对齐 iOS `RemoteSourceConfigManager`）。
class RemoteSourceConfigManager {
  /// 构造（依赖全部可注入，便于单测）。
  ///
  /// [probeClient] 用于 `manifest.version` 轻量探测（独立于两个数据源，
  /// 因探测响应不是 manifest 形状）；[proxies] 为 B-02「可配置常量」。
  RemoteSourceConfigManager({
    required RemoteManifestDatasource manifestDatasource,
    required AllSourcesDatasource allSourcesDatasource,
    required RemoteSourceRepository repository,
    required HttpClient probeClient,
    PrefsManager? prefs,
    String Function()? appVersion,
    int Function()? nowSeconds,
    List<ProxyHost> proxies = RemoteSourceStrategy.proxyHosts,
  })  : _manifestDatasource = manifestDatasource,
        _allSourcesDatasource = allSourcesDatasource,
        _repository = repository,
        _probeClient = probeClient,
        _prefs = prefs,
        _appVersion = appVersion,
        _nowSeconds = nowSeconds,
        _proxies = proxies;

  final RemoteManifestDatasource _manifestDatasource;
  final AllSourcesDatasource _allSourcesDatasource;
  final RemoteSourceRepository _repository;
  final HttpClient _probeClient;
  final PrefsManager? _prefs;
  final String Function()? _appVersion;
  final int Function()? _nowSeconds;
  final List<ProxyHost> _proxies;

  // ────────────── 契约同步键（`_group_remote_source`）──────────────

  static const String _keyEnabled = 'remote_default_source_enabled';
  static const String _keyManifestUrl = 'remote_default_manifest_url';
  static const String _keyLastVersion = 'remote_default_last_config_version';
  static const String _keyLastSyncTime = 'remote_default_last_sync_time';
  static const String _keyLastError = 'remote_default_last_sync_error';
  static const String _keyLastAppVersion = 'remote_default_last_sync_app_version';
  static const String _keyNodeBundleUrl = 'remote_node_bundle_url';
  static const String _keyNodeBundleVer = 'remote_node_bundle_ver';

  static const Set<String> managedPrefsKeys = <String>{
    _keyEnabled,
    _keyManifestUrl,
    _keyLastVersion,
    _keyLastSyncTime,
    _keyLastError,
    _keyLastAppVersion,
    _keyNodeBundleUrl,
    _keyNodeBundleVer,
  };

  PrefsManager get _p => _prefs ?? PrefsManager.instance;

  int _now() => _nowSeconds?.call() ?? TimeUtils.nowUnixSeconds();

  String _appVer() => _appVersion?.call() ?? AppInfo.version;

  // ────────────── 入口：按需同步（五级状态机）──────────────

  /// 按需同步（对齐 iOS `syncIfNeeded(force:)`）。
  Future<RemoteSourceSyncResult> syncIfNeeded({bool force = false}) async {
    // ① 开关关闭：只加载已有缓存，不联网
    final bool enabled = await _readBool(_keyEnabled, true);
    if (!enabled) return _fromCache(RemoteSourceSyncAction.skippedDisabled);

    // ② 地址留空：按「关闭同步」处理，消除必然失败的网络请求
    final String url = await _manifestUrl();
    if (url.isEmpty) {
      return _fromCache(RemoteSourceSyncAction.skippedEmptyUrl);
    }

    // ③ 从未同步过 → 必须刷新（比 App 升级更强的条件，优先判定）
    final int lastSyncTime = await _readInt(_keyLastSyncTime, 0);
    if (lastSyncTime <= 0) {
      return _syncNow(url, RemoteSourceSyncAction.firstSync);
    }

    // ④ App 版本变化 → 强制刷新（对齐 iOS「方案四」）
    final String lastAppVersion = await _readString(_keyLastAppVersion, '');
    if (_appVer() != lastAppVersion) {
      return _syncNow(url, RemoteSourceSyncAction.appVersionChanged);
    }

    // ⑤ 调用方强制
    if (force) {
      return _syncNow(url, RemoteSourceSyncAction.forceRefresh);
    }

    // ⑥ 轻量版本探测（约 30 字节，B-01 核心）
    final String? probed = await _probeVersion(url);
    if (probed != null) {
      final String lastVersion = await _readString(_keyLastVersion, '');
      if (probed != lastVersion) {
        return _syncNow(url, RemoteSourceSyncAction.versionChanged);
      }
      // 版本一致 → 跳过全量拉取（B-01 验收：版本未变不进全量）
      return _fromCache(RemoteSourceSyncAction.versionUnchanged);
    }

    // ⑦ 探测失败 → 降级到 TTL 判断（含清单自带 forceRefresh 语义）。
    //    时间基准取契约同步键（对齐 iOS shouldRefresh 读 lastSyncTime，
    //    而非仓储文件缓存的落盘时刻——两者在 syncNow 成功后一致）。
    final Result<RemoteManifest?> cachedResult = await _repository.cachedManifest();
    final RemoteManifest? cached = cachedResult.valueOrNull;
    final int ttl = cached?.ttlSeconds ?? RemoteManifest.defaultTtlSeconds;
    final bool expired = RemoteSourceStrategy.isCacheExpired(
          lastSyncEpochSeconds: lastSyncTime,
          ttlSeconds: ttl,
          nowEpochSeconds: _now(),
        ) ||
        (cached?.forceRefresh ?? false);
    if (expired) {
      return _syncNow(url, RemoteSourceSyncAction.probeFailedTtlExpired);
    }
    return _fromCache(RemoteSourceSyncAction.probeFailedUpToDate);
  }

  /// 全量同步（对齐 iOS `syncNow()`，无视缓存）。
  Future<RemoteSourceSyncResult> syncNow() async {
    final bool enabled = await _readBool(_keyEnabled, true);
    if (!enabled) return _fromCache(RemoteSourceSyncAction.skippedDisabled);
    final String url = await _manifestUrl();
    if (url.isEmpty) return _fromCache(RemoteSourceSyncAction.skippedEmptyUrl);
    return _syncNow(url, RemoteSourceSyncAction.synced);
  }

  // ────────────── 全量同步（B-02 代理链 + 兼容门控 + B-03 聚合）──────────────

  Future<RemoteSourceSyncResult> _syncNow(
    String url,
    RemoteSourceSyncAction action,
  ) async {
    // ① 拉取 manifest：仅 GitHub 域名套代理降级链（B-02，对齐 iOS fetchData）
    Result<RemoteManifest>? lastFailure;
    RemoteManifest? manifest;
    for (final String candidate
        in RemoteSourceStrategy.candidates(url, proxies: _proxies)) {
      final Result<RemoteManifest> r =
          await _manifestDatasource.fetch(candidate, forceRefresh: true);
      if (r.isSuccess) {
        manifest = r.valueOrNull;
        break;
      }
      lastFailure = r;
    }
    if (manifest == null) {
      final Failure? f = lastFailure?.failureOrNull;
      return _fail(f?.message ?? 'manifest 拉取失败');
    }

    // ② 兼容门控：manifest.minAppVersion 高于当前 App 版本 → 拒绝同步
    final String? minAppVersion = manifest.minAppVersion;
    if (minAppVersion != null &&
        minAppVersion.isNotEmpty &&
        _versionGt(minAppVersion, _appVer())) {
      final String msg =
          'manifest.minAppVersion=$minAppVersion 高于当前版本 ${_appVer()}，'
          '需升级 App 后同步';
      await _p.set(_keyLastError, msg);
      return RemoteSourceSyncResult(
        action: RemoteSourceSyncAction.incompatibleMinAppVersion,
        status: RemoteLoadStatus.failed(msg),
        manifest: await _cachedManifestOrNull(),
        error: msg,
      );
    }

    // ③ 拉取 all_sources.json（CI 合并的 6 合 1 配置；数据源内部自带代理链）
    final String allSourcesUrl = manifest.files[RemoteManifest.keyAllSources]!;
    final Result<AllSourcesContainer> allRes =
        await _allSourcesDatasource.fetch(allSourcesUrl, forceRefresh: true);
    final Failure? allFailure = allRes.failureOrNull;
    if (allFailure != null) {
      return _fail('allSources 拉取失败：${allFailure.message}');
    }
    final AllSourcesContainer container = allRes.valueOrNull!;

    // ④ 6 合 1 聚合解析（B-03）：api + spider 站点合并、disabledKeys 剔除、key 去重
    final List<Map<String, Object?>> sites =
        aggregateSites(container, disabledKeys: manifest.disabledKeys);

    // ⑤ 缓存落盘（文件缓存 + version/time 契约镜像键）
    await _repository.saveManifest(manifest);
    await _p.set(_keyLastAppVersion, _appVer());
    await _p.remove(_keyLastError);
    await _mirrorNodeBundleKeys(manifest);

    return RemoteSourceSyncResult(
      action: action,
      status: RemoteLoadStatus.loadedRemote(manifest.configVersion),
      manifest: manifest,
      sites: sites,
      fullSync: true,
    );
  }

  /// Node bundle 键镜像（对齐 iOS `syncNow` 步骤 4 之后的键写入/清除）。
  Future<void> _mirrorNodeBundleKeys(RemoteManifest manifest) async {
    final String? bundleUrl = _fileValue(manifest, 'nodeRuntimeBundle');
    if (bundleUrl != null) {
      await _p.set(_keyNodeBundleUrl, bundleUrl);
    } else {
      await _p.remove(_keyNodeBundleUrl);
    }
    final String? bundleVer = _fileValue(manifest, 'nodeRuntimeBundleVer');
    if (bundleVer != null) {
      await _p.set(_keyNodeBundleVer, bundleVer);
    } else {
      await _p.remove(_keyNodeBundleVer);
    }
  }

  String? _fileValue(RemoteManifest manifest, String key) {
    final String? v = manifest.files[key];
    if (v == null || v.isEmpty) return null;
    return v;
  }

  /// 同步失败：错误落盘 + 缓存兜底（对齐 iOS `updateFailure` + `loadCachedManifestState`）。
  Future<RemoteSourceSyncResult> _fail(String message) async {
    await _p.set(_keyLastError, message);
    return RemoteSourceSyncResult(
      action: RemoteSourceSyncAction.syncFailed,
      status: RemoteLoadStatus.failed(message),
      manifest: await _cachedManifestOrNull(),
      error: message,
    );
  }

  Future<RemoteSourceSyncResult> _fromCache(RemoteSourceSyncAction action) async {
    final RemoteManifest? cached = await _cachedManifestOrNull();
    if (cached == null) {
      return RemoteSourceSyncResult(
        action: action,
        status: const RemoteLoadStatus.idle(),
      );
    }
    return RemoteSourceSyncResult(
      action: action,
      status: RemoteLoadStatus.loadedCache(cached.configVersion),
      manifest: cached,
    );
  }

  Future<RemoteManifest?> _cachedManifestOrNull() async =>
      (await _repository.cachedManifest()).valueOrNull;

  // ────────────── 版本探测（B-01）──────────────

  /// 探测远端 `configVersion`；失败返回 null（降级 TTL 由调用方处理）。
  Future<String?> _probeVersion(String manifestUrl) async {
    final String versionUrl = versionProbeUrlFor(manifestUrl);
    for (final String candidate
        in RemoteSourceStrategy.candidates(versionUrl, proxies: _proxies)) {
      try {
        final HttpClientResponse res = await _probeClient.get(
          Uri.parse(candidate),
          headers: const <String, String>{'cache-control': 'no-cache'},
        );
        if (!res.isOk) continue;
        final Map<String, Object?>? json = JsonUtils.tryDecodeMap(res.text);
        final String version = (json?['configVersion'] ?? '').toString();
        if (version.isNotEmpty) return version;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// 从 manifest URL 派生 version 探测地址（对齐 iOS `checkManifestVersion`）：
  /// `…/manifest.json` → `…/manifest.version`；其余 → `<url>.version`。
  static String versionProbeUrlFor(String manifestUrl) {
    if (manifestUrl.endsWith('/manifest.json')) {
      return manifestUrl.replaceAll('/manifest.json', '/manifest.version');
    }
    return '$manifestUrl.version';
  }

  // ────────────── 6 合 1 聚合解析（B-03）──────────────

  /// 聚合 all_sources.json 的站点（`apiSources.sites` + `spiderSources.sites`，
  /// 「CI 自动合并的 6 合 1 配置」）：
  /// - [disabledKeys]（manifest 全局禁用列表）剔除；
  /// - key 去重（首见优先），保持原始顺序（Dart Map 插入序）；
  /// - 空 key 剔除（无法作为站点标识）。
  static List<Map<String, Object?>> aggregateSites(
    AllSourcesContainer container, {
    List<String> disabledKeys = const <String>[],
  }) {
    final Set<String> disabled = disabledKeys.toSet();
    final Map<String, Map<String, Object?>> byKey =
        <String, Map<String, Object?>>{};
    for (final Map<String, Object?> raw in container.sites) {
      final String key = (raw['key'] ?? '').toString();
      if (key.isEmpty || disabled.contains(key)) continue;
      byKey.putIfAbsent(key, () => raw);
    }
    return byKey.values.toList(growable: false);
  }

  // ────────────── 内部：prefs 读写 ──────────────

  Future<String> _manifestUrl() async {
    final String saved = await _readString(
      _keyManifestUrl,
      RemoteSourceStrategy.defaultManifestUrl,
    );
    return saved.trim();
  }

  Future<Object?> _read(String name) async {
    if (findPrefsKey(name) == null) {
      throw ArgumentError('契约外键名: $name（见 prefs_keys_v1.json）');
    }
    return _p.get(name);
  }

  Future<bool> _readBool(String name, bool fallback) async {
    final Object? v = await _read(name);
    return v is bool ? v : fallback;
  }

  Future<String> _readString(String name, String fallback) async {
    final Object? v = await _read(name);
    return v is String ? v : fallback;
  }

  Future<int> _readInt(String name, int fallback) async {
    final Object? v = await _read(name);
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// 点分版本比较：`a > b` 返回 true（逐段数值比较；段数不等短者补 0）。
  static bool _versionGt(String a, String b) {
    final List<int> pa = _versionParts(a);
    final List<int> pb = _versionParts(b);
    final int n = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < n; i++) {
      final int x = i < pa.length ? pa[i] : 0;
      final int y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _versionParts(String v) => v
      .trim()
      .split('.')
      .map((String s) => int.tryParse(s.trim()) ?? 0)
      .toList(growable: false);
}
