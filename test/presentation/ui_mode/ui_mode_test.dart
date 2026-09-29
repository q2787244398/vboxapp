/// 形态判定层单测：#10 —— `ui_mode_resolver.dart`。
///
/// ⚠️ `resolveMode` 依赖编译期平台常量；VM 测试下通过
/// `debugDefaultTargetPlatformOverride` 切换平台以覆盖各分支。
/// （`kIsWeb` 无法在 VM 测试中置真，其分支与桌面端等价，未单列。）
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/presentation/ui_mode/ui_mode_resolver.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('优先级 ①：用户显式偏好 TV（最高，先于平台常量）', () {
    test('userPrefersTv=true → tv（即使在桌面平台/小屏）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        UiModeController.resolveMode(
          userPrefersTv: true,
          screenSize: const Size(320, 480),
          hasTouch: true,
        ),
        UiMode.tv,
      );
    });

    test('userPrefersTv=false 不强制，走后续判定', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(UiModeController.resolveMode(userPrefersTv: false), UiMode.phone);
    });
  });

  group('优先级 ③：编译期平台常量（桌面端）', () {
    for (final TargetPlatform tp in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      test('$tp → desktop（无视设备特征）', () {
        debugDefaultTargetPlatformOverride = tp;
        expect(
          UiModeController.resolveMode(
            screenSize: const Size(3840, 2160),
            hasTouch: false,
            hasRemote: true,
          ),
          UiMode.desktop,
        );
        expect(UiModeController.resolveMode(), UiMode.desktop);
      });
    }
  });

  group('优先级 ②：设备特征（以 Android 为目标平台）', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('有遥控器 + 非触屏 → tv', () {
      expect(UiModeController.resolveMode(hasRemote: true, hasTouch: false),
          UiMode.tv);
      expect(UiModeController.resolveMode(hasRemote: true), UiMode.tv,
          reason: 'hasTouch 未知（null）≠ true，仍判 tv');
    });

    test('有遥控器但也是触屏 → 不因此判 tv', () {
      expect(
        UiModeController.resolveMode(
            hasRemote: true, hasTouch: true, screenSize: const Size(1080, 1920)),
        UiMode.phone,
      );
    });

    test('大屏 + 无触屏 → tv（十英尺 1280 阈值）', () {
      expect(
        UiModeController.resolveMode(
            screenSize: const Size(1920, 1080), hasTouch: false),
        UiMode.tv,
      );
      // 边界：恰好 1280 → tv
      expect(
        UiModeController.resolveMode(
            screenSize: const Size(1280, 720), hasTouch: false),
        UiMode.tv,
      );
      // 边界：1279 → phone
      expect(
        UiModeController.resolveMode(
            screenSize: const Size(1279, 720), hasTouch: false),
        UiMode.phone,
      );
    });

    test('大屏但触屏未知 / 触屏为真 → phone', () {
      expect(UiModeController.resolveMode(screenSize: const Size(1920, 1080)),
          UiMode.phone);
      expect(
        UiModeController.resolveMode(
            screenSize: const Size(1920, 1080), hasTouch: true),
        UiMode.phone,
      );
    });

    test('小屏 + 无触屏 + 无遥控 → phone', () {
      expect(
        UiModeController.resolveMode(
            screenSize: const Size(1080, 1920), hasTouch: false),
        UiMode.phone,
      );
    });

    test('无任何信号 → 兜底 phone', () {
      expect(UiModeController.resolveMode(), UiMode.phone);
    });
  });

  group('UiModeController（ChangeNotifier 接线）', () {
    test('初始为 phone；resolve 更新并通知监听者一次', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final UiModeController c = UiModeController();
      int notified = 0;
      c.addListener(() => notified++);
      expect(c.mode, UiMode.phone);

      c.resolve(hasRemote: true, hasTouch: false);
      expect(c.mode, UiMode.tv);
      expect(notified, 1);

      c.resolve(screenSize: const Size(1080, 1920), hasTouch: true);
      expect(c.mode, UiMode.phone);
      expect(notified, 2);
    });
  });
}