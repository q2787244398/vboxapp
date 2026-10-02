/// 单一页树 + 双排布（批次 A · A-08）。
///
/// 唯一真相源：`docs/第2轮开发计划_功能补全_v2.6.md` §3.3（布局适配模型）。
///
/// 收敛口径：原三套页树（phone 底栏 / tv 顶栏 / desktop 侧栏）→ **一套**：
///   · 导航项**单源** [_destinations]（同图标体系 + 同标签，全端共用）；
///   · 排布由 [AdaptiveScaffold] 按 `UiForm` 产出（竖屏底部胶囊 TabBar / 横屏左侧 Rail）；
///   · 内容区全端共用（[ShelfView] / RemoteSourcePage / LogViewerPage / BackupPage）。
///
/// 输入模态只加**反馈层**（遥控 → D-pad 焦点遍历，T.7），不改版式（§3.4）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../phone/remote_source_page.dart';
import '../ui_mode/ui_mode.dart';
import '../widgets/adaptive/adaptive.dart';
import '../widgets/backup_page.dart';
import '../widgets/input/input.dart';
import '../widgets/library_views.dart';
import '../widgets/log_viewer_page.dart';
import '../widgets/vbox/vbox.dart';

/// 书架内容：收藏 / 历史双 Tab（全端共用）。
class ShelfView extends StatelessWidget {
  /// 构造。
  const ShelfView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('vbox 书架'),
          bottom: const TabBar(
            tabs: <Widget>[Tab(text: '收藏'), Tab(text: '历史')],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[FavoritesView(), HistoryView()],
        ),
      ),
    );
  }
}

/// 首页外壳：单一页树，按形态产出双排布。
class HomeShellPage extends StatefulWidget {
  /// 构造。
  const HomeShellPage({super.key});

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  int _index = 0;

  /// 导航项单源（图标 + 标签，全端共用）。
  static const List<VboxNavItem> _destinations = <VboxNavItem>[
    VboxNavItem(
      icon: Icons.bookmark_outline,
      selectedIcon: Icons.bookmark,
      label: '书架',
    ),
    VboxNavItem(
      icon: Icons.cloud_outlined,
      selectedIcon: Icons.cloud,
      label: '远程源',
    ),
    VboxNavItem(
      icon: Icons.article_outlined,
      selectedIcon: Icons.article,
      label: '日志',
    ),
    VboxNavItem(icon: Icons.settings_backup_restore, label: '备份'),
  ];

  /// 内容区（全端共用）。
  Widget _content() => switch (_index) {
        0 => const ShelfView(),
        1 => const RemoteSourcePage(),
        2 => const LogViewerPage(),
        _ => const BackupPage(),
      };

  @override
  Widget build(BuildContext context) {
    final UiFormController controller = context.watch<UiFormController>();
    final MediaQueryData mq = MediaQuery.of(context);
    final UiForm form = controller.resolveAt(
      size: mq.size,
      orientation: mq.orientation,
    );

    final Widget shell = AdaptiveScaffold(
      form: form,
      items: _destinations,
      selectedIndex: _index,
      onSelected: (int index) => setState(() => _index = index),
      body: _content(),
    );

    // 输入模态反馈层（§3.4）：不改版式。
    //   · 遥控 → D-pad 焦点遍历（T.7）+ 十英尺缩放（§3.3，1.35× 文案档位）
    //   · 触摸 / 鼠标键盘 → 无额外包裹（hover / 快捷键由页面按需用 input/ 层）
    if (controller.modality == InputModality.remote) {
      return TenFootScaler(
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Focus(autofocus: true, child: shell),
        ),
      );
    }
    return shell;
  }
}