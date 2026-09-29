/// 形态判定（UI Mode Resolver）。
///
/// ⚠️ **占位实现**：权威设计口径见方案 §T.1（Android 侧经平台通道
/// `getUiModeType` / `hasLeanbackFeature` / `hasTouchscreen` 三重判定；
/// 桌面端为编译期常量）。本文件当前**未调用任何平台通道**，
/// [UiModeController.resolve] 的 `screenSize/hasTouch/hasRemote` 参数
/// 尚无调用方提供（见 app.dart），故真机 Android TV 现状会落到 `phone`。
/// 接线须等 `platform/system` 的 `SystemPlugin` 落地。
///
/// 判定优先级（目标态，对齐方案 T.1）：
///   ① 系统 UI Mode（Android 官方标准，经平台通道）
///   ② PackageManager 设备特征（Leanback / 触屏）
///   ③ 屏幕尺寸 + 输入设备（山寨盒子 ROM 兜底）
///   ④ 编译期平台常量（桌面端）
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// UI 形态。
enum UiMode {
  /// 手机（触屏、竖屏为主）。
  phone,

  /// Android TV（十英尺、焦点导航、遥控器）。
  tv,

  /// 桌面（Windows / macOS，鼠标键鼠）。
  desktop,
}

/// 形态判定控制器。
class UiModeController extends ChangeNotifier {
  UiMode _mode = UiMode.phone;

  UiMode get mode => _mode;

  /// 执行判定（在 App 启动时调用一次）。
  void resolve({
    Size? screenSize,
    bool? hasTouch,
    bool? hasRemote,
    bool? userPrefersTv,
  }) {
    _mode = resolveMode(
      screenSize: screenSize,
      hasTouch: hasTouch,
      hasRemote: hasRemote,
      userPrefersTv: userPrefersTv,
    );
    notifyListeners();
  }

  /// 静态判定（可单测）。
  static UiMode resolveMode({
    Size? screenSize,
    bool? hasTouch,
    bool? hasRemote,
    bool? userPrefersTv,
  }) {
    // ① 用户显式偏好（由调用方注入；目标态来自设置项，非契约 prefs 键）
    if (userPrefersTv == true) return UiMode.tv;

    // ③ 编译期平台常量（桌面端）
    if (kIsWeb) return UiMode.desktop;
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return UiMode.desktop;
    }

    // ② 设备特征
    // 遥控器存在 + 非触屏 → TV
    if (hasRemote == true && hasTouch != true) return UiMode.tv;
    // 大屏 + 无触屏 → TV（十英尺判定，参考 1920x1080）
    final Size? s = screenSize;
    if (s != null && s.width >= 1280 && hasTouch == false) return UiMode.tv;

    // 兜底：手机
    return UiMode.phone;
  }
}
