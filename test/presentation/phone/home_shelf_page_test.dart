/// 表现层 widget 测试：phone 形态书架（收藏 + 历史双 Tab）。
///
/// 直连 UseCase（D21 轻量路线），注入内存仓储 fakes 走真用例链路；
/// 覆盖空态 / 列表展示 / 移除 / 清空（确认框）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/time_utils.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/phone/home_shelf_page.dart';

import '../../support/fakes.dart';

Widget _shelf({
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
    ],
    child: const MaterialApp(home: HomeShelfPage()),
  );
}

void main() {
  testWidgets('收藏空态：显示引导文案', (WidgetTester tester) async {
    await tester.pumpWidget(_shelf());
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无收藏'), findsOneWidget);
    expect(find.text('vbox 书架'), findsOneWidget);
  });

  testWidgets('收藏列表：展示名称 / 来源 / 相对时间', (WidgetTester tester) async {
    await tester.pumpWidget(_shelf(
      favorites: <FavoriteItem>[
        FavoriteItem(
          name: '测试影片',
          laiyuan: 'demo',
          detailurl: 'u/1',
          addedAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('测试影片'), findsOneWidget);
    expect(find.textContaining('demo'), findsOneWidget);
    expect(find.textContaining('刚刚'), findsOneWidget);
  });

  testWidgets('收藏移除：点击删除后回到空态', (WidgetTester tester) async {
    await tester.pumpWidget(_shelf(
      favorites: <FavoriteItem>[
        FavoriteItem(
          id: 1,
          name: '待删除影片',
          detailurl: 'u/9',
          addedAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('待删除影片'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('待删除影片'), findsNothing);
    expect(find.textContaining('暂无收藏'), findsOneWidget);
  });

  testWidgets('收藏清空：确认框确认后列表清空', (WidgetTester tester) async {
    await tester.pumpWidget(_shelf(
      favorites: <FavoriteItem>[
        FavoriteItem(
          name: '片一',
          detailurl: 'u/1',
          addedAt: TimeUtils.nowUnixSeconds(),
        ),
        FavoriteItem(
          name: '片二',
          detailurl: 'u/2',
          addedAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('片一'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    // 确认对话框出现
    expect(find.text('确定清空全部收藏？此操作不可撤销。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(find.text('片一'), findsNothing);
    expect(find.textContaining('暂无收藏'), findsOneWidget);
  });

  testWidgets('历史 tab：空态引导', (WidgetTester tester) async {
    await tester.pumpWidget(_shelf());
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无播放历史'), findsOneWidget);
  });

  testWidgets('历史列表：展示名称 / 集数 / 进度百分比 / 进度条', (WidgetTester tester) async {
    await tester.pumpWidget(_shelf(
      history: <HistoryItem>[
        HistoryItem(
          name: '历史片',
          jishu: 3,
          detailurl: 'h/1',
          progress: 0.5,
          lastPlayedAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();

    expect(find.text('历史片'), findsOneWidget);
    expect(find.textContaining('第 3 集'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is LinearProgressIndicator && (w.value ?? 0) == 0.5,
      ),
      findsOneWidget,
    );
  });

  testWidgets('历史清空：确认框确认后清空', (WidgetTester tester) async {
    await tester.pumpWidget(_shelf(
      history: <HistoryItem>[
        HistoryItem(
          name: '历史片A',
          detailurl: 'h/1',
          lastPlayedAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('历史片A'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('确定清空全部播放历史？此操作不可撤销。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(find.text('历史片A'), findsNothing);
    expect(find.textContaining('暂无播放历史'), findsOneWidget);
  });
}
