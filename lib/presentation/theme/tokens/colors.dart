/// 设计令牌 · 颜色（批次 A · A-01）。
///
/// 唯一真相源：`docs/UI对齐基准_v1.0.md` §2.1（皮肤系统）/ §2.2（颜色令牌）。
/// 全部十六进制字面量**只允许**出现在本文件（UI 守卫 R-4）。
///
/// 对齐口径：iOS 侧没有集中式设计令牌文件，颜色以「视图私有计算属性 +
/// `Color(hex:)` 字面量」散落存在；本文件把采样结果**归纳固化**为 Flutter 令牌层。
library;

import 'package:flutter/material.dart';

/// 皮肤枚举（契约键 `app_skin_mode`，默认 `light`）。
///
/// 对齐 iOS `AppSkinMode`（[AppSettings.swift](../../../vbox/App/AppSettings.swift)）：
/// `dark` / `light` 共用同一主色 `#E11D48`，差异只在 `ColorScheme` 明暗；
/// `frosted` / `liquid` 各有独立主色。
enum VboxSkin {
  /// 浅色模式（强制 Light）。
  light('light', '浅色模式', Brightness.light),

  /// 黑暗模式（强制 Dark）。
  dark('dark', '黑暗模式', Brightness.dark),

  /// 磨砂模式（跟随系统，主色紫）。
  frosted('frosted', '磨砂模式', null),

  /// 液态模式（强制 Dark，主色天蓝）。
  liquid('liquid', '液态模式', Brightness.dark);

  const VboxSkin(this.id, this.title, this.fixedBrightness);

  /// 契约字符串值（写入 `app_skin_mode`）。
  final String id;

  /// 中文显示名（对齐 iOS `AppSkinMode.title`）。
  final String title;

  /// 该皮肤固定的配色模式；`null` = 跟随系统。
  ///
  /// 对齐 iOS `AppSkinMode.preferredColorScheme`：
  /// `dark`/`liquid` → dark，`light` → light，`frosted` → nil。
  final Brightness? fixedBrightness;

  /// 契约默认皮肤（`app_skin_mode` 默认 `light`）。
  static const VboxSkin fallback = VboxSkin.light;

  /// 解析契约字符串（未知值回退 [fallback]）。
  static VboxSkin fromId(String? id) {
    for (final VboxSkin skin in VboxSkin.values) {
      if (skin.id == id) return skin;
    }
    return fallback;
  }

  /// 皮肤主色（对齐 UI 基准 §2.1）。
  Color get primary => switch (this) {
        VboxSkin.light || VboxSkin.dark => VboxColors.skinPrimaryRose,
        VboxSkin.frosted => VboxColors.skinPrimaryPurple,
        VboxSkin.liquid => VboxColors.skinPrimarySky,
      };
}

/// 日志 / 站点分类（语义固定映射，非装饰色）。
///
/// 对齐 iOS `LogEntry.Category`（[LogViewerView.swift](../../../vbox/Views/LogViewerView.swift#L372-L386)）。
enum VboxCategory {
  /// 应用。
  app('app'),

  /// 蜘蛛。
  spider('spider'),

  /// 播放器。
  player('player'),

  /// 云盘。
  cloud('cloud'),

  /// 代理。
  proxy('proxy'),

  /// 网络。
  network('network'),

  /// 数据库。
  db('db'),

  /// 下载。
  download('download'),

  /// 福利。
  welfare('welfare'),

  /// Node。
  node('node');

  const VboxCategory(this.id);

  /// 契约字符串值。
  final String id;
}

/// 颜色令牌。
class VboxColors {
  const VboxColors._();

  // ── 皮肤主色（UI 基准 §2.1）──────────────────────────────
  /// 浅色 / 黑暗皮肤主色（玫瑰红）。
  static const Color skinPrimaryRose = Color(0xFFE11D48);

  /// 磨砂皮肤主色（紫）。
  static const Color skinPrimaryPurple = Color(0xFF7C3AED);

  /// 液态皮肤主色（天蓝）。
  static const Color skinPrimarySky = Color(0xFF38BDF8);

  // ── 资产强调色 ─────────────────────────────────────────
  /// 资产目录强调色（`AccentColor.colorset`）。
  static const Color accentAsset = Color(0xFF191919);

  // ── 语义色（UI 基准 §2.2）──────────────────────────────
  /// 选中 / 激活（播放器剧集当前项、面板选中）。
  static const Color selected = Color(0xFF2196F3);

  /// 选中胶囊（榜单胶囊填充 / 描边）。
  static const Color chipSelected = Color(0xFF34C759);

  /// 播放器深底（播放器空 / 错态背景）。
  static const Color playerBackground = Color(0xFF0F0F23);

  /// 播放器面板底色（深底 @90%，半透明覆盖层）。
  static const Color playerPanelBackground = Color(0xE60F0F23);

  /// 弹幕文字描边 / 阴影（80% 黑，提升浅底可读性）。
  static const Color danmakuShadow = Color(0xCC000000);

  /// 危险操作（文字 + 背景 @10%）。
  static const Color danger = Color(0xFFEF4444);

  /// 成功 / 就绪（授权中心「已获取 / 正常 / 就绪」；对齐 iOS `.green`）。
  ///
  /// 批次 F · F-01 新增：网盘授权状态语义色（与 [chipSelected] 同为系统绿，
  /// 但语义独立，故单列以免误用）。
  static const Color success = Color(0xFF34C759);

  /// 警告 / 过渡态（「即将过期 / 启动中 / 内存告警」；对齐 iOS `.orange`）。
  ///
  /// 批次 F · F-01 新增。
  static const Color warning = Color(0xFFFF9500);

  // ── 品牌渐变（「我的」页头部）───────────────────────────
  /// 品牌渐变起点。
  static const Color brandGradientStart = Color(0xFF3B82F6);

  /// 品牌渐变中点。
  static const Color brandGradientMid = Color(0xFF2563EB);

  /// 品牌渐变终点。
  static const Color brandGradientEnd = Color(0xFF1D4ED8);

  /// 品牌渐变（左 → 右）。
  static const List<Color> brandGradient = <Color>[
    brandGradientStart,
    brandGradientMid,
    brandGradientEnd,
  ];

  // ── 系统色（Apple HIG 语义色）───────────────────────────
  /// 系统底 · 浅（`.systemBackground`）。
  static const Color systemBackgroundLight = Color(0xFFFFFFFF);

  /// 系统底 · 深（`.systemBackground` Dark）。
  static const Color systemBackgroundDark = Color(0xFF000000);

  /// 系统分组底 · 浅（`.secondarySystemBackground`）。
  static const Color secondarySystemBackgroundLight = Color(0xFFF2F2F7);

  /// 系统分组底 · 深（`.secondarySystemBackground` Dark）。
  static const Color secondarySystemBackgroundDark = Color(0xFF1C1C1E);

  /// 次级文字 · 浅（`.secondaryLabel`，`#3C3C43` @ 60%）。
  static const Color secondaryLabelLight = Color(0x993C3C43);

  /// 次级文字 · 深（`.secondaryLabel` Dark，`#EBEBF5` @ 60%）。
  static const Color secondaryLabelDark = Color(0x99EBEBF5);

  // ── 直播分类调色板（12 色，按 `cat_N` 取模循环）──────────────
  /// 直播分类胶囊调色板（对齐 iOS `LiveCategory.palette`）。
  static const List<Color> liveCategoryPalette = <Color>[
    Color(0xFF2196F3), // blue
    Color(0xFF4CAF50), // green
    Color(0xFFF44336), // red
    Color(0xFFFF9800), // orange
    Color(0xFF9C27B0), // purple
    Color(0xFFE91E63), // pink
    Color(0xFF00BCD4), // cyan
    Color(0xFF009688), // teal
    Color(0xFF3F51B5), // indigo
    Color(0xFFFFC107), // yellow
    Color(0xFF4DB6AC), // mint
    Color(0xFF795548), // brown
  ];

  // ── 分类色板（10 色，语义固定映射）──────────────────────
  /// 分类色板（用于日志分类 / 站点标签）。
  static const Map<VboxCategory, Color> categoryColors = <VboxCategory, Color>{
    VboxCategory.app: Color(0xFF6B7280),
    VboxCategory.spider: Color(0xFF8B5CF6),
    VboxCategory.player: Color(0xFFEF4444),
    VboxCategory.cloud: Color(0xFF3B82F6),
    VboxCategory.proxy: Color(0xFF10B981),
    VboxCategory.network: Color(0xFFF59E0B),
    VboxCategory.db: Color(0xFF6366F1),
    VboxCategory.download: Color(0xFFEC4899),
    VboxCategory.welfare: Color(0xFFF97316),
    VboxCategory.node: Color(0xFF14B8A6),
  };

  // ── 网盘品牌角标底色（批次 F · F-01 授权中心 / F-06 排序列表）──────
  /// 网盘品牌角标底色（键为 `CloudDriveType.id`；采样 iOS 图标配色）。
  ///
  /// 键用字符串而非领域枚举，避免主题层反向依赖领域层（分层约束）；
  /// 未登记的键回退 [VboxColors.categoryColors] 的 `cloud` 蓝。
  static const Map<String, Color> cloudDriveBrandColors = <String, Color>{
    'ali': Color(0xFF2563EB),
    'quark': Color(0xFF3B82F6),
    'quarkNode': Color(0xFF6B7280),
    'baidu': Color(0xFFE11D48),
    'baiduNode': Color(0xFF6B7280),
    '115': Color(0xFF3B82F6),
    'uc': Color(0xFF38BDF8),
    'ucNode': Color(0xFF6B7280),
    '123pan': Color(0xFF2563EB),
    '139pan': Color(0xFF2563EB),
    '189pan': Color(0xFF3B82F6),
    'xunlei': Color(0xFF38BDF8),
    'guangya': Color(0xFF14B8A6),
    'woniu4k': Color(0xFF8B5CF6),
    'bilibili': Color(0xFFEC4899),
  };
}