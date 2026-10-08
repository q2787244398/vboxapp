/// 平台层：播放进度续播（第 5 批 · UI-F16）。
///
/// 对齐 iOS `PlayerViewsV2.restorePlaybackProgress` / `savePlaybackProgress`
/// （[L2140-L2166](../../../../vbox/Views/PlayerViewsV2.swift#L2140-L2166)）：
///  - **恢复守卫**：已存进度 `> 10` 秒才 seek（否则从头播）；
///  - **保存守卫**：当前进度 `> 5` 秒才落库，且节流 5 秒；
///  - **看完清除**：距结尾 `< 15` 秒视为看完 → 清除该视频进度。
///
/// 进度**按视频独立存储**（键 `progress_<vodId>`，单位秒）。这类**动态键**
/// 已冻结的契约 `prefs_keys_v1.json` 未登记，[PrefsManager] 对契约外键直接抛错，
/// 故与 [SkipSettings] 同口径直接走 `SharedPreferences`（等价 iOS `UserDefaults`）。
library;

import 'package:shared_preferences/shared_preferences.dart';

/// 播放进度存取与判定（纯静态，便于单测）。
class PlaybackProgressStore {
  const PlaybackProgressStore._();

  /// 恢复守卫：已存进度超过该秒数才续播（对齐 iOS `saved > 10`）。
  static const double resumeGuardSeconds = 10;

  /// 保存守卫：当前进度超过该秒数才落库（对齐 iOS `currentTime > 5`）。
  static const double saveGuardSeconds = 5;

  /// 距结尾小于该秒数视为看完（对齐 iOS `duration - currentTime < 15`）。
  static const double nearEndSeconds = 15;

  /// 落库节流间隔（对齐 iOS `lastProgressSaveAt` 的 5s）。
  static const int saveThrottleMs = 5000;

  /// 键名（对齐 iOS `playbackProgressKey(for:)` 的按视频独立语义）。
  static String keyOf(String vodId) => 'progress_$vodId';

  /// 读取指定视频的已存进度（秒；无记录 → 0）。
  static Future<double> load(String vodId) async {
    if (vodId.isEmpty) return 0;
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getDouble(keyOf(vodId)) ?? 0;
  }

  /// 写入指定视频的进度（秒）。
  static Future<void> save(String vodId, double seconds) async {
    if (vodId.isEmpty) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setDouble(keyOf(vodId), seconds);
  }

  /// 清除指定视频的进度（看完 / 从头重播时调用）。
  static Future<void> clear(String vodId) async {
    if (vodId.isEmpty) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(keyOf(vodId));
  }

  /// 是否应续播（已存进度 `> 10` 秒）。
  static bool shouldResume(double savedSeconds) =>
      savedSeconds > resumeGuardSeconds;

  /// 是否应落库（当前进度 `> 5` 秒）。
  static bool shouldSave(double positionSeconds) =>
      positionSeconds > saveGuardSeconds;

  /// 是否已到片尾（看完 → 应清除进度）。
  static bool isNearEnd(double positionSeconds, double durationSeconds) =>
      durationSeconds > 0 && durationSeconds - positionSeconds < nearEndSeconds;
}
