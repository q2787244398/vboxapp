/// 表现层 widget 测试：tv 形态（T.7 焦点规范 + TabBar 顶部导航）。
///
/// 复用共享视图（library_views / remote_source_page），注入内存仓储 fakes；
/// 覆盖三 Tab 切换、书架展示、方向键焦点切换（遥控器导航）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/time_utils.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/tv/tv_home_page.dart';

import '../../support/fakes.dart';

Widget _tv({
  List<FavoriteItem> favorites = const <FavoriteItem>[],
}) {
  return MultiProvider(
    providers: [
      Provider<FavoriteUseCases>.value(
        value: FavoriteUseCases(InMemoryFavoriteRepository(favorites)),
      ),
      Provider<HistoryUseCases>.value(
        value: HistoryUseCases(InMemoryHistoryRepository()),
      ),
      Provider<SubscriptionUseCases>.value(
        value: SubscriptionUseCases(InMemorySubscriptionRepository()),
      ),
      Provider<RemoteSourceUseCases>.value(
        value: RemoteSourceUseCases(InMemoryRemoteSourceRepository()),
      ),
    ],
    child: const MaterialApp(home: TvHomePage()),
  );
}

void main() {
  testWidgets('默认收藏 Tab：空态 + 三个顶部导航项', (WidgetTester tester) async {
    await tester.pumpWidget(_tv());
    await tester.pumpAndSettle();

    expect(find.text('vbox · tv'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('远程源'), findsOneWidget);
    expect(find.textContaining('暂无收藏'), findsOneWidget);
  });

  testWidgets('书架展示：收藏项可见（复用共享视图）', (WidgetTester tester) async {
    await tester.pumpWidget(_tv(
      favorites: <FavoriteItem>[
        FavoriteItem(
          id: 1,
          name: 'TV 片',
          laiyuan: 'demo',
          detailurl: 'u/1',
          addedAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('TV 片'), findsOneWidget);
  });

  testWidgets('历史 Tab：点击切换后显示空态', (WidgetTester tester) async {
    await tester.pumpWidget(_tv());
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无播放历史'), findsOneWidget);
  });

  testWidgets('远程源 Tab：状态卡 + 空订阅引导', (WidgetTester tester) async {
    await tester.pumpWidget(_tv());
    await tester.pumpAndSettle();

    await tester.tap(find.text('远程源'));
    await tester.pumpAndSettle();

    // TabBar label + RemoteSourcePage AppBar title
    expect(find.text('远程源'), findsNWidgets(2));
    expect(find.textContaining('未同步'), findsOneWidget);
    expect(find.textContaining('暂无订阅'), findsOneWidget);
  });

  testWidgets('T.7 焦点规范：FocusTraversalGroup + TabBar autofocus 落地', (WidgetTester tester) async {
    await tester.pumpWidget(_tv());
    await tester.pumpAndSettle();

    // 焦点遍历组 + 初始 autofocus 焦点（D-pad 真机行为归 G-10 人工验收）
    expect(find.byType(FocusTraversalGroup), findsWidgets);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });
}
