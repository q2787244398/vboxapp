/// 形态判定（UI Mode Resolver）。
///
/// 唯一真相源：方案 §2.4（⭐ 形态判定）+ T.1「三重判定，优先级递减」
///
/// 三重判定优先级（对齐方案 T.1）：
///   ① 用户显式偏好（Prefs: ui_tv_mode）—— 最高
///   ② 系统/设备特征（屏幕尺寸、遥控器、触屏）
///   ③ 编译期平台常量（desktop/mobile）
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
    // ① 用户显式偏好（最高优先级）
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
