/// 形态判定（UI Mode Resolver）。
///
/// 目标态对齐方案 §T.1 三重判定（Android 真机经平台通道）：
///   ① 系统 UI Mode（`getUiModeType`）
///   ② PackageManager 设备特征（`hasLeanbackFeature` / `hasTouchscreen`）
///   ③ 屏幕尺寸 + 输入设备（山寨盒子 ROM 兜底）
///   ④ 编译期平台常量（桌面端）
///
/// [UiModeController.resolve] 保留同步占位判定（无平台通道，供测试与桌面端）；
/// [UiModeController.resolveWithBridge] 为真机接线入口（Android 平台通道三重判定，
/// 由 app.dart 在启动时调用）。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../platform/system/system_bridge.dart';

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

  /// 真机接线入口（G-02-C）：经平台通道三重判定（方案 §T.1）。
  ///
  /// 仅在 Android 平台有意义；[screenSize] 为第 ③ 重兜底的可选尺寸
  /// （null 时跳过尺寸判定，依赖调用方注入，避免 resolver 耦合 WidgetsBinding）；
  /// [judge] 可注入判定器（默认 [resolveModeWithBridge]），单测借此隔离平台分支。
  Future<void> resolveWithBridge(
    SystemBridge bridge, {
    Size? screenSize,
    Future<UiMode> Function(SystemBridge bridge, {Size? screenSize})? judge,
  }) async {
    _mode = await (judge ?? resolveModeWithBridge)(bridge, screenSize: screenSize);
    notifyListeners();
  }

  /// 静态判定（可单测）：平台通道三重判定 + 桌面编译期常量。
  static Future<UiMode> resolveModeWithBridge(
    SystemBridge bridge, {
    Size? screenSize,
  }) async {
    // ④ 编译期平台常量（桌面端）
    if (kIsWeb || isDesktopPlatform) return UiMode.desktop;

    if (Platform.isAndroid) {
      // ① 系统 UI Mode（官方标准，最可靠）
      final bool isTelevision = await bridge.getUiModeType();
      // ② PackageManager 特性（兜底）
      final bool hasLeanback = await bridge.hasLeanbackFeature();
      final bool hasTouch = await bridge.hasTouchscreen();
      return resolveAndroidMode(
        isTelevision: isTelevision,
        hasLeanback: hasLeanback,
        hasTouch: hasTouch,
        screenSize: screenSize,
      );
    }

    return UiMode.phone;
  }

  /// 纯逻辑（可单测）：Android 三重判定（方案 §T.1 ①–③）。
  static UiMode resolveAndroidMode({
    required bool isTelevision,
    required bool hasLeanback,
    required bool hasTouch,
    Size? screenSize,
  }) {
    // ① 系统 UI Mode（官方标准，最可靠）
    if (isTelevision) return UiMode.tv;
    // ② PackageManager 特性（兜底）
    if (hasLeanback && !hasTouch) return UiMode.tv;
    // ③ 屏幕尺寸 + 输入设备（山寨盒子 ROM 兜底）
    final Size? s = screenSize;
    if (s != null && s.shortestSide >= 720 && !hasTouch) return UiMode.tv;
    return UiMode.phone;
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
