/// 数据层：SQLite 行 ↔ Dart 对象 的映射基类。
///
/// 唯一真相源：`contract/schema/schema_v1.sql`
/// 所有模型必须与该 DDL 字段严格一致（由 `scripts/check_contract_sync.py` 校验）。
///
/// 约定：
/// - 列名与 Dart 字段名**完全一致**（不做 camelCase 转换），避免映射歧义；
/// - 写入用 `toMap()`，读取用 `fromMap()`；
/// - 时间字段统一为 **Unix 秒**（INTEGER），与 iOS 端一致；
/// - 布尔字段 SQLite 存 0/1（INTEGER）。
library;

/// 可持久化为 SQLite 行的对象。
abstract class DbModel {
  /// 表名。
  static const String? table = null;

  /// 转成 SQLite 行（列名 → 值）。
  Map<String, Object?> toMap();

  /// 从 SQLite 行构造（列名 → 值）。
  static T fromMap<T>(Map<String, Object?> map) {
    throw UnimplementedError('子类必须实现 fromMap');
  }
}

/// SQLite 布尔读写辅助（0/1 ↔ bool）。
bool readBool(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

/// 布尔 → SQLite 整数。
int writeBool(bool v) => v ? 1 : 0;

/// 读取可空字符串（NULL → null）。
String? readNullableString(Object? v) => v as String?;

/// Unix 秒 → DateTime（本地时区）。
DateTime readTime(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch((v as int) * 1000);

/// DateTime → Unix 秒。
int writeTime(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
