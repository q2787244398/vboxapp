/// 呈现层单测：UiModeResolver（G-02-C 三重判定接线）。
///
/// 覆盖：`resolveAndroidMode` 纯逻辑（方案 §T.1 ①–③）、`resolveModeWithBridge`
/// （fake 桥）、`UiModeController.resolveWithBridge`（notify）、
/// 以及保留的同步 `resolveMode` 行为。无 IO、无原生依赖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/platform/system/system_bridge.dart';
import 'package:vbox/presentation/ui_mode/ui_mode_resolver.dart';

// ─────────────── 测试替身 ───────────────

/// 假系统桥：按注入值返回三通道结果（记录调用）。
class _FakeSystemBridge implements SystemBridge {
  _FakeSystemBridge({this.isTelevision = false});

  bool isTelevision;
  bool hasLeanback = false;
  bool hasTouch = true;
  final List<String> calls = <String>[];

  @override
  Future<bool> getUiModeType() async {
    calls.add('getUiModeType');
    return isTelevision;
  }

  @override
  Future<bool> hasLeanbackFeature() async {
    calls.add('hasLeanbackFeature');
    return hasLeanback;
  }

  @override
  Future<bool> hasTouchscreen() async {
    calls.add('hasTouchscreen');
    return hasTouch;
  }
}

void main() {
  group('UiModeController.resolveAndroidMode（方案 §T.1 ①–③）', () {
    test('① 系统 UI Mode = TV → tv（优先于其余判定）', () {
      expect(
        UiModeController.resolveAndroidMode(
          isTelevision: true,
          hasLeanback: false,
          hasTouch: true,
        ),
        UiMode.tv,
      );
    });

    test('② Leanback 特性且无触屏 → tv', () {
      expect(
        UiModeController.resolveAndroidMode(
          isTelevision: false,
          hasLeanback: true,
          hasTouch: false,
        ),
        UiMode.tv,
      );
    });

    test('③ 大屏(≥720)且无触屏 → tv（山寨盒子兜底）', () {
      expect(
        UiModeController.resolveAndroidMode(
          isTelevision: false,
          hasLeanback: false,
          hasTouch: false,
          screenSize: const Size(1280, 720),
        ),
        UiMode.tv,
      );
      // 有触屏的大屏 → 非 TV
      expect(
        UiModeController.resolveAndroidMode(
          isTelevision: false,
          hasLeanback: false,
          hasTouch: true,
          screenSize: const Size(1280, 720),
        ),
        UiMode.phone,
      );
      // 尺寸不足（< 720）→ 非 TV
      expect(
        UiModeController.resolveAndroidMode(
          isTelevision: false,
          hasLeanback: false,
          hasTouch: false,
          screenSize: const Size(400, 600),
        ),
        UiMode.phone,
      );
      // 未提供尺寸 → 跳过第 ③ 重 → 非 TV
      expect(
        UiModeController.resolveAndroidMode(
          isTelevision: false,
          hasLeanback: false,
          hasTouch: false,
        ),
        UiMode.phone,
      );
    });

    test('默认（触屏手机）→ phone', () {
      expect(
        UiModeController.resolveAndroidMode(
          isTelevision: false,
          hasLeanback: false,
          hasTouch: true,
        ),
        UiMode.phone,
      );
    });
  });

  group('UiModeController.resolveModeWithBridge', () {
    test('桌面平台 → desktop（不触碰通道）', () async {
      final _FakeSystemBridge bridge = _FakeSystemBridge(isTelevision: true);
      final UiMode m = await UiModeController.resolveModeWithBridge(bridge);
      expect(m, UiMode.desktop);
      expect(bridge.calls, isEmpty);
    });
  });

  group('UiModeController.resolveWithBridge（控制器接线）', () {
    test('Android TV（① 命中）→ notify 且 mode = tv', () async {
      final UiModeController c = UiModeController()..resolve();
      expect(c.mode, UiMode.phone);
      int notified = 0;
      c.addListener(() => notified++);

      await c.resolveWithBridge(
        _FakeSystemBridge(isTelevision: true),
        // 注入判定器隔离平台分支（测试环境为桌面平台，默认判定不可达 Android 分支）
        judge: (SystemBridge b, {Size? screenSize}) async =>
            UiModeController.resolveAndroidMode(
          isTelevision: await b.getUiModeType(),
          hasLeanback: await b.hasLeanbackFeature(),
          hasTouch: await b.hasTouchscreen(),
          screenSize: screenSize,
        ),
      );

      expect(c.mode, UiMode.tv);
      expect(notified, 1);
    });
  });

  group('UiModeController.resolveMode（保留的同步占位判定）', () {
    test('遥控器 + 非触屏 → tv；桌面常量 → desktop；默认 phone', () {
      expect(
        UiModeController.resolveMode(hasRemote: true, hasTouch: false),
        UiMode.tv,
      );
      expect(
        UiModeController.resolveMode(
          screenSize: const Size(1920, 1080),
          hasTouch: false,
        ),
        UiMode.tv,
      );
      expect(UiModeController.resolveMode(), UiMode.phone);
    });
  });
}
