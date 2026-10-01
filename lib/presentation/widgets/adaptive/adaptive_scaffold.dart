/// 自适应框架 · 自适应外壳（批次 A · A-07）。
///
/// 唯一真相源：`docs/第2轮开发计划_功能补全_v2.5.md` §3.3（导航）：
///   竖屏 → 底部悬浮胶囊 TabBar；横屏 → 左侧 NavigationRail（同图标 + 同标签）。
/// 内容最大宽度：横屏居中约束 1440–1680dp（[maxContentWidth]，默认 1680）。
///
/// 一套页面代码：导航项 [items] 与内容 [body] 全端共用，仅排布随形态切换。
library;

import 'package:flutter/material.dart';

import '../../ui_mode/ui_mode.dart';
import '../vbox/vbox_nav.dart';

/// 自适应外壳：TabBar ↔ Rail 由 [form] 决定，内容区约束最大宽度。
class AdaptiveScaffold extends StatelessWidget {
  /// 构造。
  const AdaptiveScaffold({
    super.key,
    required this.form,
    required this.body,
    this.items = const <VboxNavItem>[],
    this.selectedIndex = 0,
    this.onSelected,
    this.title,
    this.actions = const <Widget>[],
    this.leading,
    this.railExtended = false,
    this.maxContentWidth = 1680,
    this.backgroundColor,
  });

  /// 当前形态。
  final UiForm form;

  /// 内容区（全端共用）。
  final Widget body;

  /// 导航项（空则不渲染导航）。
  final List<VboxNavItem> items;

  /// 当前选中索引。
  final int selectedIndex;

  /// 选择回调。
  final ValueChanged<int>? onSelected;

  /// 顶栏标题（null → 不渲染 AppBar）。
  final String? title;

  /// 顶栏操作。
  final List<Widget> actions;

  /// 侧栏顶部组件（横屏）。
  final Widget? leading;

  /// 侧栏是否展开（横屏）。
  final bool railExtended;

  /// 内容区最大宽度（横屏居中约束）。
  final double maxContentWidth;

  /// 底色（缺省取主题）。
  final Color? backgroundColor;

  /// 内容区：统一走「居中 + 最大宽度约束」，使竖横切换时内容子树保持一致。
  Widget _content(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: body,
        ),
      );

  PreferredSizeWidget? _appBar() {
    if (title == null) return null;
    return AppBar(
      title: Text(title!),
      actions: actions,
      backgroundColor: backgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final PreferredSizeWidget? appBar = _appBar();
    final Widget content = SafeArea(child: _content(context));

    if (form.isLandscape) {
      return Scaffold(
        appBar: appBar,
        backgroundColor: backgroundColor,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (items.isNotEmpty)
              VboxNavRail(
                items: items,
                selectedIndex: selectedIndex,
                onSelected: onSelected ?? (_) {},
                extended: railExtended,
                leading: leading,
              ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      body: content,
      bottomNavigationBar: items.isEmpty
          ? null
          : VboxBottomNav(
              items: items,
              selectedIndex: selectedIndex,
              onSelected: onSelected ?? (_) {},
            ),
    );
  }
}