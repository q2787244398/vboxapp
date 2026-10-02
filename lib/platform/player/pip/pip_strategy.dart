/// 平台层：画中画策略（批次 C · C-05 PiP 多策略）。
///
/// 对齐 iOS `PlayerCore/` 的 **PiP 5 策略**（MDK / MPV / VT / ViewCapture /
/// AVPlayer 代理，见 `docs/第2轮开发方案_iOS全量复核_v1.3.md` §2.2 项 13）：
/// 按「渲染内核 + 平台能力」选择画中画的承载方式。
///
/// 三端差异（D6 播放器策略）：
///  - Android：Media3 → **MDK**（系统画中画 API 26+）；libVLC/libmpv 回退 → **MPV**
///    （系统承载或浮窗兜底）；系统 PiP 不可用 → **ViewCapture**（应用内浮窗）
///  - Windows / Linux：无系统级 PiP API → **MPV**（libmpv 渲染 + 应用内浮窗）
///  - macOS / iOS：AVPlayer 主后端 → **AVPlayer**（系统画中画）；不可用 → ViewCapture
///  - 未启用 / 平台不可用：**none**（调用方隐藏入口）
library;

import '../../../domain/entities/player/player.dart';

/// 画中画承载策略（5 类 + 降级 none）。
enum PipStrategy {
  /// MDK 渲染（Android Media3）→ 系统级画中画。
  mdk,

  /// libmpv 渲染 → 桌面应用内浮窗 / 系统承载。
  mpv,

  /// VideoToolbox 渲染 → 系统级画中画（iOS/macOS 视频工具链）。
  vt,

  /// 视图捕获 → 应用内浮窗（无系统 PiP API 时的兜底）。
  viewCapture,

  /// AVPlayer 代理 → 系统级画中画（iOS/macOS 主后端）。
  avPlayer,

  /// 未启用 / 平台不可用 → 降级（调用方隐藏入口）。
  none;

  /// 是否走系统级画中画承载（true → 原生系统桥；false → 应用内浮窗）。
  bool get isSystemBased => switch (this) {
        PipStrategy.mdk || PipStrategy.vt || PipStrategy.avPlayer => true,
        PipStrategy.mpv || PipStrategy.viewCapture || PipStrategy.none => false,
      };
}

/// 画中画策略判定（C-05）。
///
/// 规则（对齐 iOS 渲染内核 → PiP 承载映射 + 三端平台能力）：
/// - `enabled=false` → [PipStrategy.none]（契约 `player_pip_enabled` 未开启）；
/// - iOS / macOS → [PipStrategy.avPlayer]（系统 PiP）或 [PipStrategy.viewCapture] 兜底；
/// - Windows / Linux → [PipStrategy.mpv]（libmpv 渲染，无系统 PiP API → 应用内浮窗）；
/// - Android → [PipStrategy.mdk]（Media3 主后端）/ [PipStrategy.mpv]（回退后端），
///   系统 PiP 不可用 → [PipStrategy.viewCapture]。
class PipStrategyResolver {
  PipStrategyResolver._();

  /// 由平台 / 当前后端 / 系统 PiP 可用性解析策略。
  ///
  /// [backend] 为当前播放后端（未 open 时 null）；[systemPipAvailable]
  /// 由调用方经原生桥探测（Android API 26+ / macOS AVKit 能力）。
  static PipStrategy resolve({
    required bool enabled,
    required String platform,
    required PlayerBackend? backend,
    required bool systemPipAvailable,
  }) {
    if (!enabled) return PipStrategy.none;
    switch (platform.toLowerCase()) {
      case 'ios':
      case 'macos':
        return systemPipAvailable ? PipStrategy.avPlayer : PipStrategy.viewCapture;
      case 'windows':
      case 'linux':
        // 无系统级 PiP API → libmpv 渲染的应用内浮窗承载。
        return PipStrategy.mpv;
      case 'android':
      case 'fuchsia':
        if (!systemPipAvailable) return PipStrategy.viewCapture;
        return backend == PlayerBackend.media3 ? PipStrategy.mdk : PipStrategy.mpv;
      default:
        return PipStrategy.none;
    }
  }
}
