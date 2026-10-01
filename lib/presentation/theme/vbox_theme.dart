/// 主题工厂（批次 A · A-03）。
///
/// 唯一真相源：`docs/UI对齐基准_v1.0.md` §2.1（四皮肤）· §2.2（颜色）· §2.3（字体）。
///
/// 目标：消费契约键 `app_skin_mode` / `app_skin_follows_system`，为四套皮肤
/// 产出等价 [ThemeData]，并在运行时热切换（R-1 皮肤令牌一致）。
library;

import 'package:flutter/material.dart';

import 'tokens/colors.dart';
import 'tokens/typography.dart';

/// 主题工厂。
class VboxTheme {
  const VboxTheme._();

  /// 解析该皮肤「期望的配色模式」（`null` = 跟随系统）。
  ///
  /// 逐行对齐 iOS `AppSettings.preferredColorScheme`：
  /// ```swift
  /// if skinFollowsSystem { return skinMode == .liquid ? .dark : nil }
  /// if skinMode == .liquid { return .dark }
  /// if skinMode == .frosted { return nil }
  /// return skinMode.preferredColorScheme
  /// ```
  static Brightness? preferredBrightness(VboxSkin skin, bool followsSystem) {
    if (followsSystem) {
      return skin == VboxSkin.liquid ? Brightness.dark : null;
    }
    if (skin == VboxSkin.liquid) return Brightness.dark;
    if (skin == VboxSkin.frosted) return null;
    return skin.fixedBrightness;
  }

  /// 解析最终配色模式：皮肤固定值优先，`null` 时回退系统亮度。
  static Brightness resolveBrightness({
    required VboxSkin skin,
    required bool followsSystem,
    required Brightness systemBrightness,
  }) =>
      preferredBrightness(skin, followsSystem) ?? systemBrightness;

  /// 按皮肤 + 配色模式构建 [ThemeData]。
  static ThemeData build({
    required VboxSkin skin,
    required Brightness brightness,
  }) {
    final bool isDark = brightness == Brightness.dark;
    final Color primary = skin.primary;
    final Color systemBackground = isDark
        ? VboxColors.systemBackgroundDark
        : VboxColors.systemBackgroundLight;
    final Color groupedBackground = isDark
        ? VboxColors.secondarySystemBackgroundDark
        : VboxColors.secondarySystemBackgroundLight;
    final Color secondaryLabel =
        isDark ? VboxColors.secondaryLabelDark : VboxColors.secondaryLabelLight;

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      surface: systemBackground,
      surfaceContainerHighest: groupedBackground,
      onSurfaceVariant: secondaryLabel,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // iOS `secondarySystemBackground`（分组底）为页面底色；卡片用 `surface`（系统底）。
      scaffoldBackgroundColor: groupedBackground,
      textTheme: VboxTypography.buildTextTheme(
        primaryText: scheme.onSurface,
        secondaryText: secondaryLabel,
      ),
    );
  }
}