/// 表现层 widget 测试：desktop 形态（NavigationRail 宽屏布局）。
///
/// 复用共享视图（library_views / remote_source_page），注入内存仓储 fakes；
/// 覆盖形态切换（书架 ↔ 远程源）、书架展示、远程源操作。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/time_utils.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/desktop/desktop_home_page.dart';

import '../../support/fakes.dart';

Widget _desktop({
  List<FavoriteItem> favorites = const <FavoriteItem>[],
  List<HistoryItem> history = const <HistoryItem>[],
}) {
  return MultiProvider(
    providers: [
      Provider<FavoriteUseCases>.value(
        value: FavoriteUseCases(InMemoryFavoriteRepository(favorites)),
      ),
      Provider<HistoryUseCases>.value(
        value: HistoryUseCases(InMemoryHistoryRepository(history)),
      ),
      Provider<SubscriptionUseCases>.value(
        value: SubscriptionUseCases(InMemorySubscriptionRepository()),
      ),
      Provider<RemoteSourceUseCases>.value(
        value: RemoteSourceUseCases(InMemoryRemoteSourceRepository()),
      ),
    ],
    child: const MaterialApp(home: DesktopHomePage()),
  );
}

void main() {
  testWidgets('默认书架：显示收藏 / 历史 Tab 与导航栏', (WidgetTester tester) async {
    await tester.pumpWidget(_desktop());
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsOneWidget);
    expect(find.text('远程源'), findsOneWidget);
    expect(find.text('vbox 书架'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.textContaining('暂无收藏'), findsOneWidget);
  });

  testWidgets('书架展示：收藏项可见（复用共享视图）', (WidgetTester tester) async {
    await tester.pumpWidget(_desktop(
      favorites: <FavoriteItem>[
        FavoriteItem(
          id: 1,
          name: '桌面片',
          laiyuan: 'demo',
          detailurl: 'u/1',
          addedAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('桌面片'), findsOneWidget);
  });

  testWidgets('切到远程源：状态卡 + 空订阅引导', (WidgetTester tester) async {
    await tester.pumpWidget(_desktop());
    await tester.pumpAndSettle();

    await tester.tap(find.text('远程源'));
    await tester.pumpAndSettle();

    // NavigationRail label + RemoteSourcePage AppBar title
    expect(find.text('远程源'), findsNWidgets(2));
    expect(find.textContaining('未同步'), findsOneWidget);
    expect(find.textContaining('暂无订阅'), findsOneWidget);
  });

  testWidgets('远程源添加订阅：对话框输入后列表出现', (WidgetTester tester) async {
    await tester.pumpWidget(_desktop());
    await tester.pumpAndSettle();

    await tester.tap(find.text('远程源'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('订阅')); // FAB
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '桌面源');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://example.com/desktop.json',
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.text('桌面源'), findsOneWidget);
    expect(find.textContaining('https://example.com/desktop.json'), findsOneWidget);
  });

  testWidgets('切回书架：收藏仍可用', (WidgetTester tester) async {
    await tester.pumpWidget(_desktop());
    await tester.pumpAndSettle();

    await tester.tap(find.text('远程源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();

    expect(find.text('vbox 书架'), findsOneWidget);
    expect(find.textContaining('暂无收藏'), findsOneWidget);
  });
}
