/// tv 形态：遥控器（D-pad）导航首页。
///
/// 遵循 T.7 焦点规范：`FocusTraversalGroup`（WidgetOrder 策略）+ 顶部 TabBar 导航
/// （左右方向键切换），复用三形态共享视图（`library_views` / `remote_source_page`）。
/// G-01 tv 块（登记见 VBOX_PLAN 附录 C）。
library;

import 'package:flutter/material.dart';

import '../phone/remote_source_page.dart';
import '../widgets/backup_page.dart';
import '../widgets/library_views.dart';
import '../widgets/log_viewer_page.dart';

/// tv 首页。
class TvHomePage extends StatelessWidget {
  /// 构造。
  const TvHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('vbox · tv'),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(48),
              child: Focus(
                autofocus: true,
                child: TabBar(
                  tabs: <Widget>[
                    Tab(text: '收藏'),
                    Tab(text: '历史'),
                    Tab(text: '远程源'),
                    Tab(text: '日志'),
                    Tab(text: '备份'),
                  ],
                ),
              ),
            ),
          ),
          body: const TabBarView(
            children: <Widget>[
              FavoritesView(),
              HistoryView(),
              RemoteSourcePage(),
              LogViewerPage(),
              BackupPage(),
            ],
          ),
        ),
      ),
    );
  }
}
