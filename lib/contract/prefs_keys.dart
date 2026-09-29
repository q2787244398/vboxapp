/// 契约层：Preferences 键名
///
/// 唯一真相源：`contract/schema/prefs_keys_v1.json`（63 键 + 5 敏感键）
/// 本文件是该契约的 Dart 移植，**任何修改必须同步两侧**。
///
/// 提取依据：iOS 源码 `vbox/` 中的 `UserDefaults ... forKey:`（D1：iOS 为契约来源）。
/// 全部 63 键均可在 iOS 源码中定位；不得新增契约外键名。
///
/// ⚠️ 敏感键（[kSensitiveKeys]）不得写入 SharedPreferences，
///    必须走 flutter_secure_storage。
library;

/// 键名分组（严格对应 JSON 契约 `keys` 下的 13 个 `_group_*` 分组）。
enum PrefsGroup {
  /// 订阅
  subscription,

  /// Spider 解析
  spider,

  /// 远程源
  remoteSource,

  /// 播放器
  player,

  /// 缓冲
  buffer,

  /// TMDB
  tmdb,

  /// 弹幕
  danmaku,

  /// 直播电视
  liveTv,

  /// 壹平台（One Platform）
  onePlatform,

  /// 夸克 / PG
  quarkPg,

  /// 福利
  welfare,

  /// 调试
  debug,

  /// 遗留迁移
  legacyMigration,
}

/// JSON 契约中 `_group_*` 分组名 ↔ 本枚举 的映射（用于一致性校验）。
const Map<String, PrefsGroup> kGroupNameToEnum = <String, PrefsGroup>{
  '_group_subscription': PrefsGroup.subscription,
  '_group_spider': PrefsGroup.spider,
  '_group_remote_source': PrefsGroup.remoteSource,
  '_group_player': PrefsGroup.player,
  '_group_buffer': PrefsGroup.buffer,
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
    required this.sensitive,
    this.defaultValue,
    this.description = '',
  });

  /// 键名字符串（写入存储的 key）。
  final String name;

  /// 所属分组。
  final PrefsGroup group;

  /// 是否敏感（敏感键必须走 secure storage）。
  final bool sensitive;

  /// 默认值（与 iOS 端 `UserDefaults` 注册默认值对齐；无默认则为 null）。
  final Object? defaultValue;

  /// 说明。
  final String description;
}

// ─────────────────────────────────────────────────────────────
// 63 个契约键（顺序与 `prefs_keys_v1.json` 的 `keys` 分组顺序一致）
// ─────────────────────────────────────────────────────────────

/// 全部 Prefs 键（63 个），严格按契约分组排列。
const List<PrefsKey> kAllPrefsKeys = <PrefsKey>[
  // ────────────── _group_subscription（3）──────────────
  PrefsKey(name: 'subscribed_config_urls', group: PrefsGroup.subscription, sensitive: false, description: '已订阅配置 URL 列表'),
  PrefsKey(name: 'active_subscription_index', group: PrefsGroup.subscription, sensitive: false, description: '当前激活订阅索引'),
  PrefsKey(name: 'cached_subscribe_config', group: PrefsGroup.subscription, sensitive: false, description: '订阅配置缓存'),

  // ────────────── _group_spider（4）──────────────
  PrefsKey(name: 'fallback_enabled', group: PrefsGroup.spider, sensitive: false, description: '启用回退解析'),
  PrefsKey(name: 'enable_dual_mode', group: PrefsGroup.spider, sensitive: false, description: '启用双形态'),
  PrefsKey(name: 'custom_fallback_sites', group: PrefsGroup.spider, sensitive: false, description: '自定义回退站点'),
  PrefsKey(name: 'user_parsers', group: PrefsGroup.spider, sensitive: false, description: '用户自定义解析器'),

  // ────────────── _group_remote_source（9）──────────────
  PrefsKey(name: 'remote_default_source_enabled', group: PrefsGroup.remoteSource, sensitive: false, description: '启用远程默认源'),
  PrefsKey(name: 'bundle_sources_enabled', group: PrefsGroup.remoteSource, sensitive: false, description: '启用内置源'),
  PrefsKey(name: 'remote_default_manifest_url', group: PrefsGroup.remoteSource, sensitive: false, description: '远程 manifest 地址'),
  PrefsKey(name: 'remote_default_last_config_version', group: PrefsGroup.remoteSource, sensitive: false, description: '远程配置版本'),
  PrefsKey(name: 'remote_default_last_sync_time', group: PrefsGroup.remoteSource, sensitive: false, description: '远程上次同步时间'),
  PrefsKey(name: 'remote_default_last_sync_error', group: PrefsGroup.remoteSource, sensitive: false, description: '远程上次同步错误'),
  PrefsKey(name: 'remote_default_last_sync_app_version', group: PrefsGroup.remoteSource, sensitive: false, description: '远程上次同步 App 版本'),
  PrefsKey(name: 'remote_node_bundle_url', group: PrefsGroup.remoteSource, sensitive: false, description: '远程 Node bundle 地址'),
  PrefsKey(name: 'remote_node_bundle_ver', group: PrefsGroup.remoteSource, sensitive: false, description: '远程 Node bundle 版本'),

  // ────────────── _group_player（7）──────────────
  PrefsKey(name: 'player_auto_play_next', group: PrefsGroup.player, sensitive: false, description: '自动连播'),
  PrefsKey(name: 'player_background_play', group: PrefsGroup.player, sensitive: false, description: '后台播放'),
  PrefsKey(name: 'player_long_press_speed', group: PrefsGroup.player, sensitive: false, description: '长按倍速'),
  PrefsKey(name: 'player_pip_enabled', group: PrefsGroup.player, sensitive: false, description: '画中画'),
  PrefsKey(name: 'positionTimerIntervalMs', group: PrefsGroup.player, sensitive: false, description: '进度计时器间隔（ms）'),
  PrefsKey(name: 'networkTimeout', group: PrefsGroup.player, sensitive: false, description: '网络超时'),
  PrefsKey(name: 'reconnect', group: PrefsGroup.player, sensitive: false, description: '重连'),

  // ────────────── _group_buffer（6）──────────────
  PrefsKey(name: 'bufferedPosition', group: PrefsGroup.buffer, sensitive: false, description: '已缓冲位置'),
  PrefsKey(name: 'maxBufferDuration', group: PrefsGroup.buffer, sensitive: false, description: '最大缓冲时长'),
  PrefsKey(name: 'highBufferDuration', group: PrefsGroup.buffer, sensitive: false, description: '高水位缓冲时长'),
  PrefsKey(name: 'startBufferDuration', group: PrefsGroup.buffer, sensitive: false, description: '起始缓冲时长'),
  PrefsKey(name: 'maxDelayTime', group: PrefsGroup.buffer, sensitive: false, description: '最大延迟时间'),
  PrefsKey(name: 'timeout', group: PrefsGroup.buffer, sensitive: false, description: '缓冲超时'),

  // ────────────── _group_tmdb（3）──────────────
  PrefsKey(name: 'app_tmdb_proxy_url', group: PrefsGroup.tmdb, sensitive: false, description: 'TMDB 代理地址'),
  PrefsKey(name: 'app_tmdb_proxy_token', group: PrefsGroup.tmdb, sensitive: true, description: '🔒 TMDB 代理令牌'),
  PrefsKey(name: 'app_tmdb_use_token', group: PrefsGroup.tmdb, sensitive: false, description: 'TMDB 使用令牌'),

  // ────────────── _group_danmaku（3）──────────────
  PrefsKey(name: 'custom_danmaku_source_enabled', group: PrefsGroup.danmaku, sensitive: false, description: '启用自定义弹幕源'),
  PrefsKey(name: 'custom_danmaku_source_url', group: PrefsGroup.danmaku, sensitive: false, description: '自定义弹幕源地址'),
  PrefsKey(name: 'danmaku_scroll', group: PrefsGroup.danmaku, sensitive: false, description: '弹幕滚动'),

  // ────────────── _group_live_tv（6）──────────────
  PrefsKey(name: 'live_tv_local_channels', group: PrefsGroup.liveTv, sensitive: false, description: '本地直播频道'),
  PrefsKey(name: 'mdtv_home_tabs', group: PrefsGroup.liveTv, sensitive: false, description: 'MDTV 首页标签'),
  PrefsKey(name: 'mdtv_iv_idx', group: PrefsGroup.liveTv, sensitive: false, description: 'MDTV IV 索引'),
  PrefsKey(name: 'mdtv_key_idx', group: PrefsGroup.liveTv, sensitive: false, description: 'MDTV key 索引'),
  PrefsKey(name: 'mdtv_key_verified', group: PrefsGroup.liveTv, sensitive: false, description: 'MDTV key 已验证'),
  PrefsKey(name: 'mdtv_mode_idx', group: PrefsGroup.liveTv, sensitive: false, description: 'MDTV 模式索引'),

  // ────────────── _group_one_platform（5）──────────────
  PrefsKey(name: 'one_platform_iv_idx', group: PrefsGroup.onePlatform, sensitive: false, description: '壹平台 IV 索引'),
  PrefsKey(name: 'one_platform_key_idx', group: PrefsGroup.onePlatform, sensitive: false, description: '壹平台 key 索引'),
  PrefsKey(name: 'one_platform_token', group: PrefsGroup.onePlatform, sensitive: true, description: '🔒 壹平台令牌'),
  PrefsKey(name: 'one_platform_userkey', group: PrefsGroup.onePlatform, sensitive: true, description: '🔒 壹平台用户密钥'),
  PrefsKey(name: 'one_platform_uuid', group: PrefsGroup.onePlatform, sensitive: true, description: '🔒 壹平台 UUID'),

  // ────────────── _group_quark_pg（10）──────────────
  PrefsKey(name: 'pg_ali_auto_cleanup', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里自动清理'),
  PrefsKey(name: 'pg_ali_cleanup_delay', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里清理延迟'),
  PrefsKey(name: 'pg_ali_enabled', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里启用'),
  PrefsKey(name: 'pg_ali_is_vip', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里会员'),
  PrefsKey(name: 'pg_ali_proxy_port', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里代理端口'),
  PrefsKey(name: 'pg_ali_thread_limit', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里线程上限'),
  PrefsKey(name: 'pg_ali_thread_night', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里夜间线程'),
  PrefsKey(name: 'pg_ali_transfer_dir', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里转存目录'),
  PrefsKey(name: 'pg_ali_vod_flags', group: PrefsGroup.quarkPg, sensitive: false, description: 'PG 阿里点播标记'),
  PrefsKey(name: 'quark_device_id', group: PrefsGroup.quarkPg, sensitive: true, description: '🔒 夸克设备 ID'),

  // ────────────── _group_welfare（2）──────────────
  PrefsKey(name: 'welfare_platform_order', group: PrefsGroup.welfare, sensitive: false, description: '福利平台顺序'),
  PrefsKey(name: 'fuli_remote_platform_order_v2', group: PrefsGroup.welfare, sensitive: false, description: '福利远程平台顺序 v2'),

  // ────────────── _group_debug（4）──────────────
  PrefsKey(name: 'show_debug_overlay', group: PrefsGroup.debug, sensitive: false, description: '显示调试浮层'),
  PrefsKey(name: 'show_search_debug', group: PrefsGroup.debug, sensitive: false, description: '显示搜索调试'),
  PrefsKey(name: 'searchHistory', group: PrefsGroup.debug, sensitive: false, description: '搜索历史'),
  PrefsKey(name: 'dns_cache_clear', group: PrefsGroup.debug, sensitive: false, description: '清除 DNS 缓存'),

  // ────────────── _group_legacy_migration（1）──────────────
  PrefsKey(name: 'vbox_sqlite_migration_done', group: PrefsGroup.legacyMigration, sensitive: false, description: 'SQLite 迁移已完成'),
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
