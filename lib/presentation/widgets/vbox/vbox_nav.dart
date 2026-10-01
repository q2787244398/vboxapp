/// 统一组件库 · 导航（批次 A · A-04）。
///
/// 唯一真相源：`docs/UI对齐基准_v1.0.md` §4.1（底部 Tab）/ §4.2（桌面 NavigationRail）。
/// 视觉语言（色 / 字号）对齐 §2；交互形态按端适配（原则 2）。
library;

import 'package:flutter/material.dart';

import '../../theme/tokens/typography.dart';

/// 导航项（共享模型，供底栏与侧栏复用）。
class VboxNavItem {
  /// 构造。
  const VboxNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  /// 默认图标。
  final IconData icon;

  /// 选中图标（缺省回退 [icon]）。
  final IconData? selectedIcon;

  /// 文案。
  final String label;
}

/// 底部导航（手机形态，对齐 iOS 六 Tab 骨架）。
class VboxBottomNav extends StatelessWidget {
  /// 构造。
  const VboxBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// 导航项。
  final List<VboxNavItem> items;

  /// 当前索引。
  final int selectedIndex;

  /// 选择回调。
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: VboxTypography.s11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        destinations: <Widget>[
          for (final VboxNavItem item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon ?? item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

/// 侧边导航（桌面形态，替代底部 Tab）。
class VboxNavRail extends StatelessWidget {
  /// 构造。
  const VboxNavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.extended = false,
    this.labelType = NavigationRailLabelType.all,
    this.leading,
    this.trailing,
  });

  /// 导航项。
  final List<VboxNavItem> items;

  /// 当前索引。
  final int selectedIndex;

  /// 选择回调。
  final ValueChanged<int> onSelected;

  /// 是否展开（显示文字）。
  final bool extended;

  /// 标签展示方式（[extended] 为真时忽略）。
  final NavigationRailLabelType? labelType;

  /// 顶部组件。
  final Widget? leading;

  /// 底部组件。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return NavigationRailTheme(
      data: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        selectedLabelTextStyle: TextStyle(
          fontSize: VboxTypography.s12,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: VboxTypography.s12,
          color: scheme.onSurfaceVariant,
        ),
      ),
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        extended: extended,
        labelType: extended ? null : labelType,
        groupAlignment: -0.9,
        leading: leading,
        trailing: trailing,
        destinations: <NavigationRailDestination>[
          for (final VboxNavItem item in items)
            NavigationRailDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon ?? item.icon),
              label: Text(item.label),
            ),
        ],
      ),
    );
  }
}