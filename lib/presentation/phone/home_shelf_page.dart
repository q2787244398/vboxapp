/// phone 形态：书架首页（收藏 + 历史双 Tab）。
///
/// 视图逻辑在 `widgets/library_views.dart`（三形态共享，直连 UseCase），
/// 本文件仅负责 phone 形态壳：AppBar（含远程源入口）+ TabBar 容器。
/// G-01 phone 书架块（登记见 VBOX_PLAN 附录 C）。
library;

import 'package:flutter/material.dart';

import '../widgets/backup_page.dart';
import '../widgets/library_views.dart';
import '../widgets/log_viewer_page.dart';
import 'remote_source_page.dart';

/// 书架首页。
class HomeShelfPage extends StatelessWidget {
  /// 构造。
  const HomeShelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('vbox 书架'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.cloud_outlined),
              tooltip: '远程源',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const RemoteSourcePage(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.article_outlined),
              tooltip: '日志',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const LogViewerPage(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: '备份与还原',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const BackupPage(),
                ),
              ),
            ),
          ],
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
