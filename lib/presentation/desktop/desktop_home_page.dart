/// desktop 形态：宽屏布局（左侧 NavigationRail + 右侧内容区）。
///
/// 复用三形态共享视图（`widgets/library_views.dart` 的书架、`remote_source_page.dart` 的远程源、
/// `log_viewer_page.dart` 的日志），形态差异仅在布局壳。
/// G-01 desktop 块（登记见 VBOX_PLAN 附录 C）；A3 增补日志入口。
library;

import 'package:flutter/material.dart';

import '../phone/remote_source_page.dart';
import '../widgets/backup_page.dart';
import '../widgets/library_views.dart';
import '../widgets/log_viewer_page.dart';

/// desktop 首页。
class DesktopHomePage extends StatefulWidget {
  /// 构造。
  const DesktopHomePage({super.key});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (int index) =>
                setState(() => _index = index),
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.6,
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                icon: Icon(Icons.bookmark_outline),
                selectedIcon: Icon(Icons.bookmark),
                label: Text('书架'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_outlined),
                selectedIcon: Icon(Icons.cloud),
                label: Text('远程源'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.article_outlined),
                selectedIcon: Icon(Icons.article),
                label: Text('日志'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_backup_restore),
                label: Text('备份'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return switch (_index) {
      0 => const _DesktopShelfView(),
      1 => const RemoteSourcePage(),
      2 => const LogViewerPage(),
      _ => const BackupPage(),
    };
  }
}

/// 书架内容区：收藏 / 历史 Tab（复用共享视图）。
class _DesktopShelfView extends StatelessWidget {
  const _DesktopShelfView();

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