/// 设计令牌 · 字体（批次 A · A-02）。
///
/// 唯一真相源：`docs/UI对齐基准_v1.0.md` §2.3。
///
/// 口径：**字号对齐，字体族不强制** —— iOS 全部使用系统字体（SF Pro / 苹方），
/// 字号实测集合为 `10 / 11 / 12 / 13 / 14 / 15 / 16 / 18 / 24 / 28`。
/// Flutter 侧统一走系统字体，只锁定字号档位（UI 守卫 R-3）。
library;

import 'package:flutter/material.dart';

/// 字体令牌。
class VboxTypography {
  const VboxTypography._();

  // ── 字号档位（10 档，UI 基准 §2.3）───────────────────────
  /// 10 · 角标 / 辅助说明。
  static const double s10 = 10;

  /// 11 · Tab 文字。
  static const double s11 = 11;

  /// 12 · 次级正文。
  static const double s12 = 12;

  /// 13 · 列表副标题 / 标签。
  static const double s13 = 13;

  /// 14 · 正文。
  static const double s14 = 14;

  /// 15 · 列表主标题。
  static const double s15 = 15;

  /// 16 · 区块标题（semibold）。
  static const double s16 = 16;

  /// 18 · 弹窗标题 / 大号按钮。
  static const double s18 = 18;

  /// 24 · 页面主标题。
  static const double s24 = 24;

  /// 28 · 空态标题。
  static const double s28 = 28;

  /// 全部字号档位（升序；供守卫 R-3 白名单与单测断言）。
  static const List<double> scale = <double>[
    s10,
    s11,
    s12,
    s13,
    s14,
    s15,
    s16,
    s18,
    s24,
    s28,
  ];

  /// 构建语义化 [TextTheme]（颜色由调用方按当前 ColorScheme 注入）。
  ///
  /// 语义映射对齐 UI 基准 §2.3 档位表。
  static TextTheme buildTextTheme({
    required Color primaryText,
    required Color secondaryText,
  }) {
    TextStyle style(double size, FontWeight weight, Color color) =>
        TextStyle(fontSize: size, fontWeight: weight, color: color);

    return TextTheme(
      // 页面主标题 / 空态标题
      displaySmall: style(s28, FontWeight.w700, primaryText),
      headlineMedium: style(s24, FontWeight.w700, primaryText),
      // 弹窗标题 / 大号按钮
      titleLarge: style(s18, FontWeight.w600, primaryText),
      // 区块标题
      titleMedium: style(s16, FontWeight.w600, primaryText),
      // 列表主标题
      titleSmall: style(s15, FontWeight.w500, primaryText),
      // 正文
      bodyLarge: style(s14, FontWeight.w400, primaryText),
      // 次级正文
      bodyMedium: style(s13, FontWeight.w400, secondaryText),
      bodySmall: style(s12, FontWeight.w400, secondaryText),
      // Tab 文字 / 角标
      labelLarge: style(s11, FontWeight.w500, primaryText),
      labelSmall: style(s10, FontWeight.w400, secondaryText),
    );
  }
}