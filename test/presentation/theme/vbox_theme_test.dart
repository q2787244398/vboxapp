/// 呈现层单测：主题工厂（批次 A · A-03）。
///
/// 验收：① `preferredBrightness` 逐条对齐 iOS `AppSettings.preferredColorScheme`；
/// ② 四皮肤构建的 [ThemeData] 主色与枚举一致（R-1）。纯逻辑，无 IO。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/presentation/theme/theme.dart';

void main() {
  group('VboxTheme.preferredBrightness（对齐 iOS AppSettings）', () {
    test('跟随系统：仅 liquid 强制 dark，其余返回 null', () {
      expect(VboxTheme.preferredBrightness(VboxSkin.light, true), isNull);
      expect(VboxTheme.preferredBrightness(VboxSkin.dark, true), isNull);
      expect(VboxTheme.preferredBrightness(VboxSkin.frosted, true), isNull);
      expect(VboxTheme.preferredBrightness(VboxSkin.liquid, true), Brightness.dark);
    });

    test('不跟随系统：light→light / dark→dark / frosted→null / liquid→dark', () {
      expect(VboxTheme.preferredBrightness(VboxSkin.light, false), Brightness.light);
      expect(VboxTheme.preferredBrightness(VboxSkin.dark, false), Brightness.dark);
      expect(VboxTheme.preferredBrightness(VboxSkin.frosted, false), isNull);
      expect(VboxTheme.preferredBrightness(VboxSkin.liquid, false), Brightness.dark);
    });
  });

  group('VboxTheme.resolveBrightness', () {
    test('固定值优先；null 回退系统亮度', () {
      expect(
        VboxTheme.resolveBrightness(
          skin: VboxSkin.light,
          followsSystem: false,
          systemBrightness: Brightness.dark,
        ),
        Brightness.light,
      );
      expect(
        VboxTheme.resolveBrightness(
          skin: VboxSkin.frosted,
          followsSystem: false,
          systemBrightness: Brightness.dark,
        ),
        Brightness.dark,
      );
    });
  });

  group('VboxTheme.build（四皮肤主色 R-1）', () {
    test('四皮肤 × 明暗两态，主色与枚举一致', () {
      for (final VboxSkin skin in VboxSkin.values) {
        for (final Brightness b in Brightness.values) {
          final ThemeData theme = VboxTheme.build(skin: skin, brightness: b);
          expect(theme.useMaterial3, isTrue);
          expect(theme.brightness, b);
          expect(theme.colorScheme.brightness, b);
          expect(theme.colorScheme.primary, skin.primary);
        }
      }
    });

    test('页面底色取分组底；画布层取系统底', () {
      final ThemeData light = VboxTheme.build(
        skin: VboxSkin.light,
        brightness: Brightness.light,
      );
      expect(light.scaffoldBackgroundColor, VboxColors.secondarySystemBackgroundLight);
      expect(light.colorScheme.surface, VboxColors.systemBackgroundLight);

      final ThemeData dark = VboxTheme.build(
        skin: VboxSkin.dark,
        brightness: Brightness.dark,
      );
      expect(dark.scaffoldBackgroundColor, VboxColors.secondarySystemBackgroundDark);
      expect(dark.colorScheme.surface, VboxColors.systemBackgroundDark);
    });

    test('字体主题注入当前配色（字号档位受控）', () {
      final ThemeData theme = VboxTheme.build(
        skin: VboxSkin.light,
        brightness: Brightness.light,
      );
      expect(theme.textTheme.titleMedium?.fontSize, VboxTypography.s16);
      expect(theme.textTheme.bodyLarge?.fontSize, VboxTypography.s14);
    });
  });
}