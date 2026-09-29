/// 数据层：远程源仓储实现。
///
/// 组成：清单数据源（HTTP 拉取 + 校验）+ 本地缓存文件 + 契约同步键。
/// - 缓存清单落盘于 `StoragePaths.cacheDir/remote_manifest.json`（原子写）；
/// - 同时镜像写入契约键 `remote_default_last_config_version`（string）
///   与 `remote_default_last_sync_time`（long，Unix 秒）；
/// - manifest 地址取自契约键 `remote_default_manifest_url`（用户可覆盖）。
///
/// 边界约定：内层异常统一用 [Failure.from] 归一，方法只返回 `Result`。
library;

import '../../core/errors/failures.dart';
import '../../core/storage/file_store.dart';
import '../../core/storage/storage_paths.dart';
import '../../core/utils/result.dart';
import '../../core/utils/time_utils.dart';
import '../../domain/entities/remote_source/remote_source.dart';
import '../../domain/repositories/remote_source_repository.dart';
import '../datasources/local/prefs_manager.dart';
import '../datasources/remote/remote_manifest_datasource.dart';

/// 远程源仓储实现。
class RemoteSourceRepositoryImpl implements RemoteSourceRepository {
  /// 构造（[prefs] / [cacheFilePath] 便于单测注入）。
  RemoteSourceRepositoryImpl({
    required RemoteManifestDatasource datasource,
    PrefsManager? prefs,
    String? cacheFilePath,
  })  : _datasource = datasource,
        _prefs = prefs,
        _cacheFilePath = cacheFilePath;

  final RemoteManifestDatasource _datasource;
  final PrefsManager? _prefs;
  final String? _cacheFilePath;

  /// 缓存清单文件名。
  static const String cacheFileName = 'remote_manifest.json';

  /// 缓存包裹内的时间戳键。
  static const String cachedAtKey = 'cachedAtSeconds';

  /// 缓存包裹内的清单键。
  static const String manifestKey = 'manifest';

  PrefsManager get _p => _prefs ?? PrefsManager.instance;

  String get _cachePath =>
      _cacheFilePath ?? FileStore.join(StoragePaths.cacheDir, cacheFileName);

  @override
  Future<Result<RemoteManifest>> fetchManifest({bool forceRefresh = false}) async {
    try {
      final String url = (await _p.remoteManifestUrl()).trim();
      if (url.isEmpty) {
        return Err<RemoteManifest>(
          const ValidationFailure('未配置 manifest 地址（remote_default_manifest_url）'),
        );
      }
      return await _datasource.fetch(url, forceRefresh: forceRefresh);
    } catch (e) {
      return Err<RemoteManifest>(Failure.from(e));
    }
  }

  @override
  Future<Result<RemoteManifest?>> cachedManifest() async {
    try {
      final Map<String, Object?>? box = await FileStore.readJsonMap(_cachePath);
      final Object? raw = box?[manifestKey];
      if (raw is! Map) return Success<RemoteManifest?>(null);
      return Success<RemoteManifest?>(
        RemoteManifest.fromJson(raw.cast<String, Object?>()),
      );
    } catch (e) {
      return Err<RemoteManifest?>(Failure.from(e));
    }
  }

  @override
  Future<Result<bool>> saveManifest(RemoteManifest manifest) async {
    try {
      final int now = TimeUtils.nowUnixSeconds();
      await FileStore.writeJson(_cachePath, <String, Object?>{
        cachedAtKey: now,
        manifestKey: manifest.toJson(),
      });
      await _p.set('remote_default_last_config_version', manifest.configVersion);
      await _p.set('remote_default_last_sync_time', now);
      return Success<bool>(true);
    } catch (e) {
      return Err<bool>(Failure.from(e));
    }
  }

  @override
  Future<Result<bool>> needsRefresh(int nowSeconds) async {
    final Result<int> atResult = await cachedAtSeconds();
    final Failure? failure = atResult.failureOrNull;
    if (failure != null) return Err<bool>(failure);

    final int cachedAt = atResult.valueOrNull ?? 0;
    // 无缓存：恒需要刷新
    if (cachedAt <= 0) return Success<bool>(true);

    final Result<RemoteManifest?> cachedResult = await cachedManifest();
    final Failure? cacheFailure = cachedResult.failureOrNull;
    if (cacheFailure != null) return Err<bool>(cacheFailure);

    final int ttl =
        cachedResult.valueOrNull?.ttlSeconds ?? RemoteManifest.defaultTtlSeconds;
    return Success<bool>(nowSeconds - cachedAt >= ttl);
  }

  @override
  Future<Result<int>> cachedAtSeconds() async {
    try {
      final Map<String, Object?>? box = await FileStore.readJsonMap(_cachePath);
      final Object? raw = box?[cachedAtKey];
      return Success<int>(raw is num ? raw.toInt() : 0);
    } catch (e) {
      return Err<int>(Failure.from(e));
    }
  }
}