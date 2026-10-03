/// 数据层：网盘授权凭据存储（批次 F · F-03）。
///
/// 对齐 iOS `SecureCredentialStore`（`vbox/Services/SecureCredentialStore.swift`）：
/// - 凭据字典 → Keychain 账号 **`cloud_drive_credentials_v1`**
///   （契约 `storage: keychain`，序列化形态 `{ "<driveType>": <credential> }` JSON）
/// - 明文 Token 键 **`saved_drive_tokens_v1`**（契约 keychain）与遗留键
///   **`saved_drive_tokens`**（契约 sensitive，iOS 侧为 UserDefaults 遗留）
///
/// 本类只做「领域对象 ↔ JSON ↔ [PrefsManager]」的编解码；
/// **安全存储路由由 [PrefsManager] 按契约 `storage`/`sensitive` 判定**，
/// 故凭据绝不会落明文 SharedPreferences（由 `prefs_manager_test` 逐键锁定）。
library;

import 'dart:convert';

import '../../../domain/entities/cloud/cloud_drive.dart';
import 'prefs_manager.dart';

/// 网盘凭据存储。
class CloudDriveCredentialStore {
  /// 构造（注入契约偏好管理器）。
  CloudDriveCredentialStore(this._prefs);

  final PrefsManager _prefs;

  /// 凭据字典键（契约 `storage: keychain`）。
  static const String storageKey = 'cloud_drive_credentials_v1';

  /// 明文 Token 存储键（契约 `storage: keychain`）。
  static const String savedTokensV1Key = 'saved_drive_tokens_v1';

  /// 遗留 Token 键（契约 `sensitive`，iOS 侧为 UserDefaults 遗留）。
  static const String savedTokensKey = 'saved_drive_tokens';

  /// 读取全部凭据（`driveType` → 凭据）。
  Future<Map<String, CloudDriveCredential>> loadAll() async {
    final Object? raw = await _prefs.get(storageKey);
    if (raw is! String || raw.isEmpty) {
      return <String, CloudDriveCredential>{};
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return <String, CloudDriveCredential>{};
    }
    if (decoded is! Map) return <String, CloudDriveCredential>{};

    final Map<String, CloudDriveCredential> out =
        <String, CloudDriveCredential>{};
    for (final MapEntry<Object?, Object?> entry in decoded.entries) {
      final Object? value = entry.value;
      if (entry.key == null || value is! Map) continue;
      final Map<String, dynamic> map = <String, dynamic>{
        for (final MapEntry<Object?, Object?> f in value.entries)
          f.key.toString(): f.value,
      };
      final CloudDriveCredential credential = CloudDriveCredential.fromJson(map);
      if (credential.driveType.isNotEmpty) {
        out[entry.key.toString()] = credential;
      }
    }
    return out;
  }

  /// 读取单个网盘凭据（不存在返回 null）。
  Future<CloudDriveCredential?> credential(CloudDriveType type) async =>
      (await loadAll())[type.id];

  /// 写入单个网盘凭据（覆盖）。
  Future<void> save(CloudDriveCredential credential) async {
    final Map<String, CloudDriveCredential> all = await loadAll();
    all[credential.driveType] = credential;
    await saveAll(all);
  }

  /// 全量写入（覆盖）。
  Future<void> saveAll(Map<String, CloudDriveCredential> credentials) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      for (final MapEntry<String, CloudDriveCredential> e
          in credentials.entries)
        e.key: e.value.toJson(),
    };
    await _prefs.set(storageKey, jsonEncode(payload));
  }

  /// 删除某网盘凭据。
  Future<void> remove(CloudDriveType type) async {
    final Map<String, CloudDriveCredential> all = await loadAll();
    if (all.remove(type.id) != null) {
      await saveAll(all);
    }
  }

  /// 清空全部凭据（谨慎：授权中心「全部登出」用）。
  Future<void> clear() async => _prefs.remove(storageKey);

  /// 是否已持有可用密钥（授权中心「已获取」判定）。
  Future<bool> hasCredentials(CloudDriveType type) async =>
      (await credential(type))?.hasSecret ?? false;
}
