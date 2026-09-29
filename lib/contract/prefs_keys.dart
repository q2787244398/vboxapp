/// 契约层：Preferences 键名
///
/// 唯一真相源：`contract/schema/prefs_keys_v1.json`（v1.1，53 键 + 5 敏感键）
/// 本文件是该契约的 Dart 移植，**任何修改必须同步两侧**。
///
/// 提取依据：iOS 源码 `vbox/` 中的 `UserDefaults.standard` 调用
///          （含 `forKey:` 实调用、`let xKey = "k"` 常量、`enum XXXKeys` 键常量三种写法）。
/// D1：iOS 为契约来源；不得新增契约外键名。
///
/// v1.1 修订（2026-09-29）：移除 10 个误抓的非 prefs 键（播放器 KVC 属性 / CA 动画 key）。
/// 详见 `contract/docs/prefs_keys_revision_v1.1.md`。
///
/// ⚠️ 敏感键（[kSensitiveKeys]）不得写入 SharedPreferences，
///    必须走 flutter_secure_storage。读取时需兼容 iOS 写入的 UserDefaults 值。
library;

/// 键值类型（对应契约 JSON 的 `type` 字段）。
enum PrefsType {
  string,
  stringArray,
  bool,
  int,
  long,
  float;

  /// 从契约 JSON 的 type 字符串解析。
  static PrefsType fromJson(String s) => switch (s) {
        'string' => PrefsType.string,
        'stringArray' => PrefsType.stringArray,
        'bool' => PrefsType.bool,
        'int' => PrefsType.int,
        'long' => PrefsType.long,
        'float' => PrefsType.float,
        _ => throw ArgumentError('未知 Prefs 类型: $s'),
      };
}

/// 键名分组（严格对应 JSON 契约 `keys` 下的 12 个 `_group_*` 分组）。
enum PrefsGroup {
  subscription,
  spider,
  remoteSource,
  player,
  tmdb,
  danmaku,
  liveTv,
  onePlatform,
  quarkPg,
  welfare,
  debug,
  legacyMigration,
}

/// JSON 契约 `_group_*` 分组名 ↔ 本枚举 的映射（用于一致性校验）。
const Map<String, PrefsGroup> kGroupNameToEnum = <String, PrefsGroup>{
  '_group_subscription': PrefsGroup.subscription,
  '_group_spider': PrefsGroup.spider,
  '_group_remote_source': PrefsGroup.remoteSource,
  '_group_player': PrefsGroup.player,
  '_group_tmdb': PrefsGroup.tmdb,
  '_group_danmaku': PrefsGroup.danmaku,
  '_group_live_tv': PrefsGroup.liveTv,
  '_group_one_platform': PrefsGroup.onePlatform,
  '_group_quark_pg': PrefsGroup.quarkPg,
  '_group_welfare': PrefsGroup.welfare,
  '_group_debug': PrefsGroup.debug,
  '_group_legacy_migration': PrefsGroup.legacyMigration,
};

/// 单个 Prefs 键的元数据。
class PrefsKey {
  const PrefsKey({
    required this.name,
    required this.group,
    required this.type,
    this.sensitive = false,
    this.defaultValue,
    this.description = '',
  });

  /// 键名字符串（写入存储的 key）。
  final String name;

  /// 所属分组。
  final PrefsGroup group;

  /// 值类型（决定 SharedPreferences 用哪个 getter）。
  final PrefsType type;

  /// 是否敏感（敏感键必须走 secure storage）。
  final bool sensitive;

  /// 默认值（与 iOS `UserDefaults` 注册默认值对齐）。
  final Object? defaultValue;

  /// 说明。
  final String description;
}

// ─────────────────────────────────────────────────────────────
// 53 个契约键（顺序与 `prefs_keys_v1.json` 的分组顺序一致）
// ─────────────────────────────────────────────────────────────

const List<PrefsKey> kAllPrefsKeys = <PrefsKey>[
  // ────────────── _group_subscription（3）──────────────
  PrefsKey(name: 'subscribed_config_urls', group: PrefsGroup.subscription, type: PrefsType.stringArray, defaultValue: <String>[], description: '订阅源 URL 列表'),
  PrefsKey(name: 'active_subscription_index', group: PrefsGroup.subscription, type: PrefsType.int, defaultValue: 0, description: '当前激活订阅源索引'),
  PrefsKey(name: 'cached_subscribe_config', group: PrefsGroup.subscription, type: PrefsType.string, description: '订阅 JSON 缓存（建议不迁移）'),

  // ────────────── _group_spider（4）──────────────
  PrefsKey(name: 'fallback_enabled', group: PrefsGroup.spider, type: PrefsType.bool, defaultValue: true, description: '兜底源开关'),
  PrefsKey(name: 'enable_dual_mode', group: PrefsGroup.spider, type: PrefsType.bool, defaultValue: true, description: '双模式（type=3 HTTP API 走原生链路）'),
  PrefsKey(name: 'custom_fallback_sites', group: PrefsGroup.spider, type: PrefsType.string, defaultValue: '[]', description: '自定义兜底源（JSON 数组字符串）'),
  PrefsKey(name: 'user_parsers', group: PrefsGroup.spider, type: PrefsType.string, defaultValue: '[]', description: '用户自定义解析器（JSON）'),

  // ────────────── _group_remote_source（9）──────────────
  PrefsKey(name: 'remote_default_source_enabled', group: PrefsGroup.remoteSource, type: PrefsType.bool, defaultValue: true, description: '启用远程默认源'),
  PrefsKey(name: 'bundle_sources_enabled', group: PrefsGroup.remoteSource, type: PrefsType.bool, defaultValue: false, description: '启用内置源（兼容模式）'),
  PrefsKey(name: 'remote_default_manifest_url', group: PrefsGroup.remoteSource, type: PrefsType.string, defaultValue: 'https://vbox-ai.github.io/api/sources/manifest.json', description: 'manifest 地址'),
  PrefsKey(name: 'remote_default_last_config_version', group: PrefsGroup.remoteSource, type: PrefsType.string, defaultValue: '', description: '上次同步的 configVersion'),
  PrefsKey(name: 'remote_default_last_sync_time', group: PrefsGroup.remoteSource, type: PrefsType.long, description: '上次同步时间戳'),
  PrefsKey(name: 'remote_default_last_sync_error', group: PrefsGroup.remoteSource, type: PrefsType.string, description: '上次同步错误'),
  PrefsKey(name: 'remote_default_last_sync_app_version', group: PrefsGroup.remoteSource, type: PrefsType.string, description: '上次同步时的 App 版本'),
  PrefsKey(name: 'remote_node_bundle_url', group: PrefsGroup.remoteSource, type: PrefsType.string, description: 'Node bundle 远程地址'),
  PrefsKey(name: 'remote_node_bundle_ver', group: PrefsGroup.remoteSource, type: PrefsType.string, description: 'Node bundle 版本'),

  // ────────────── _group_player（4）──────────────
  PrefsKey(name: 'player_auto_play_next', group: PrefsGroup.player, type: PrefsType.bool, defaultValue: true, description: '自动播放下一集'),
  PrefsKey(name: 'player_background_play', group: PrefsGroup.player, type: PrefsType.bool, defaultValue: false, description: '后台播放'),
  PrefsKey(name: 'player_long_press_speed', group: PrefsGroup.player, type: PrefsType.float, defaultValue: 2.0, description: '长按倍速'),
  PrefsKey(name: 'player_pip_enabled', group: PrefsGroup.player, type: PrefsType.bool, defaultValue: true, description: '画中画开关'),

  // ────────────── _group_tmdb（3）──────────────
  PrefsKey(name: 'app_tmdb_proxy_url', group: PrefsGroup.tmdb, type: PrefsType.string, defaultValue: '', description: 'TMDB 代理地址'),
  PrefsKey(name: 'app_tmdb_proxy_token', group: PrefsGroup.tmdb, type: PrefsType.string, sensitive: true, defaultValue: '', description: '🔒 TMDB 代理 token'),
  PrefsKey(name: 'app_tmdb_use_token', group: PrefsGroup.tmdb, type: PrefsType.bool, defaultValue: false, description: 'TMDB 使用 token'),

  // ────────────── _group_danmaku（2）──────────────
  PrefsKey(name: 'custom_danmaku_source_enabled', group: PrefsGroup.danmaku, type: PrefsType.bool, defaultValue: false, description: '自定义弹幕源'),
  PrefsKey(name: 'custom_danmaku_source_url', group: PrefsGroup.danmaku, type: PrefsType.string, defaultValue: '', description: '弹幕源地址'),

  // ────────────── _group_live_tv（6）──────────────
  PrefsKey(name: 'live_tv_local_channels', group: PrefsGroup.liveTv, type: PrefsType.string, defaultValue: '[]', description: '本地直播频道（JSON）'),
  PrefsKey(name: 'mdtv_home_tabs', group: PrefsGroup.liveTv, type: PrefsType.string, defaultValue: '[]', description: 'MDTV 首页 Tab'),
  PrefsKey(name: 'mdtv_iv_idx', group: PrefsGroup.liveTv, type: PrefsType.int, defaultValue: 0, description: 'MDTV IV 索引'),
  PrefsKey(name: 'mdtv_key_idx', group: PrefsGroup.liveTv, type: PrefsType.int, defaultValue: 0, description: 'MDTV Key 索引'),
  PrefsKey(name: 'mdtv_key_verified', group: PrefsGroup.liveTv, type: PrefsType.bool, defaultValue: false, description: 'MDTV Key 已校验'),
  PrefsKey(name: 'mdtv_mode_idx', group: PrefsGroup.liveTv, type: PrefsType.int, defaultValue: 0, description: 'MDTV 模式索引'),

  // ────────────── _group_one_platform（5）──────────────
  PrefsKey(name: 'one_platform_iv_idx', group: PrefsGroup.onePlatform, type: PrefsType.int, defaultValue: 0, description: 'One 平台 IV 索引'),
  PrefsKey(name: 'one_platform_key_idx', group: PrefsGroup.onePlatform, type: PrefsType.int, defaultValue: 0, description: 'One 平台 Key 索引'),
  PrefsKey(name: 'one_platform_token', group: PrefsGroup.onePlatform, type: PrefsType.string, sensitive: true, defaultValue: '', description: '🔒 One 平台 token'),
  PrefsKey(name: 'one_platform_userkey', group: PrefsGroup.onePlatform, type: PrefsType.string, sensitive: true, defaultValue: '', description: '🔒 One 平台 userkey'),
  PrefsKey(name: 'one_platform_uuid', group: PrefsGroup.onePlatform, type: PrefsType.string, sensitive: true, defaultValue: '', description: '🔒 One 平台 UUID'),

  // ────────────── _group_quark_pg（10）──────────────
  PrefsKey(name: 'pg_ali_auto_cleanup', group: PrefsGroup.quarkPg, type: PrefsType.bool, defaultValue: false, description: '自动清理'),
  PrefsKey(name: 'pg_ali_cleanup_delay', group: PrefsGroup.quarkPg, type: PrefsType.int, defaultValue: 60, description: '清理延迟(s)'),
  PrefsKey(name: 'pg_ali_enabled', group: PrefsGroup.quarkPg, type: PrefsType.bool, defaultValue: false, description: '启用 PG'),
  PrefsKey(name: 'pg_ali_is_vip', group: PrefsGroup.quarkPg, type: PrefsType.bool, defaultValue: false, description: 'VIP 状态'),
  PrefsKey(name: 'pg_ali_proxy_port', group: PrefsGroup.quarkPg, type: PrefsType.int, defaultValue: 58090, description: '代理端口'),
  PrefsKey(name: 'pg_ali_thread_limit', group: PrefsGroup.quarkPg, type: PrefsType.int, defaultValue: 3, description: '线程上限'),
  PrefsKey(name: 'pg_ali_thread_night', group: PrefsGroup.quarkPg, type: PrefsType.int, defaultValue: 5, description: '夜间线程'),
  PrefsKey(name: 'pg_ali_transfer_dir', group: PrefsGroup.quarkPg, type: PrefsType.string, defaultValue: '', description: '转存目录'),
  PrefsKey(name: 'pg_ali_vod_flags', group: PrefsGroup.quarkPg, type: PrefsType.string, defaultValue: '', description: 'VOD 标志'),
  PrefsKey(name: 'quark_device_id', group: PrefsGroup.quarkPg, type: PrefsType.string, sensitive: true, defaultValue: '', description: '🔒 夸克设备 ID'),

  // ────────────── _group_welfare（2）──────────────
  PrefsKey(name: 'welfare_platform_order', group: PrefsGroup.welfare, type: PrefsType.string, defaultValue: '[]', description: '福利平台排序（JSON）'),
  PrefsKey(name: 'fuli_remote_platform_order_v2', group: PrefsGroup.welfare, type: PrefsType.string, defaultValue: '[]', description: '福利远程平台排序 v2'),

  // ────────────── _group_debug（4）──────────────
  PrefsKey(name: 'show_debug_overlay', group: PrefsGroup.debug, type: PrefsType.bool, defaultValue: false, description: '调试浮层'),
  PrefsKey(name: 'show_search_debug', group: PrefsGroup.debug, type: PrefsType.bool, defaultValue: false, description: '搜索调试'),
  PrefsKey(name: 'searchHistory', group: PrefsGroup.debug, type: PrefsType.string, defaultValue: '[]', description: '搜索历史（JSON）'),
  PrefsKey(name: 'dns_cache_clear', group: PrefsGroup.debug, type: PrefsType.bool, defaultValue: false, description: 'DNS 缓存清理'),

  // ────────────── _group_legacy_migration（1）──────────────
  PrefsKey(name: 'vbox_sqlite_migration_done', group: PrefsGroup.legacyMigration, type: PrefsType.bool, defaultValue: false, description: 'UserDefaults→SQLite 迁移标记。Flutter 首次启动必须识别，避免重复迁移'),
];

/// 敏感键名集合（5 个，严格对应 JSON 契约 `sensitiveKeys`）。
const Set<String> kSensitiveKeys = <String>{
  'app_tmdb_proxy_token',
  'one_platform_token',
  'one_platform_userkey',
  'one_platform_uuid',
  'quark_device_id',
};

/// 全部键名集合。
final Set<String> kAllKeyNames = <String>{
  for (final PrefsKey k in kAllPrefsKeys) k.name,
};

/// 按键名查找元数据。
PrefsKey? findPrefsKey(String name) {
  for (final PrefsKey k in kAllPrefsKeys) {
    if (k.name == name) return k;
  }
  return null;
}

/// 判断某键是否敏感。
bool isSensitiveKey(String name) => kSensitiveKeys.contains(name);

/// 按分组列出键。
List<PrefsKey> keysOfGroup(PrefsGroup group) =>
    kAllPrefsKeys.where((PrefsKey k) => k.group == group).toList();
