/// 单一页树 + 双排布单测（批次 A · A-08）。
///
/// 覆盖：竖屏（底部胶囊 TabBar）/ 横屏（左侧 Rail）双排布、单一导航项单源、
/// 内容区全端共用（书架 / 远程源）、遥控模态焦点遍历（T.7）。
/// 形态以 [UiFormController] 的 override 强制（与真机视口解耦，判定分支可穷举）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/time_utils.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/shell/home_shell_page.dart';
import 'package:vbox/presentation/ui_mode/ui_mode_resolver.dart';
import 'package:vbox/presentation/widgets/input/input.dart';

import '../../support/fakes.dart';

Widget _shell({
  UiFormOverride override = UiFormOverride.portrait,
  bool isTv = false,
  List<FavoriteItem> favorites = const <FavoriteItem>[],
  List<HistoryItem> history = const <HistoryItem>[],
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UiFormController>.value(
        value: UiFormController(
          env: UiFormEnv(
            override: override,
            isTv: isTv,
            hasDpad: isTv,
            hasTouch: !isTv,
          ),
        ),
      ),
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
      Provider<ContentBrowseUseCases>.value(
        value: buildContentBrowseUseCases(),
      ),
    ],
    child: const MaterialApp(home: HomeShellPage()),
  );
}

void main() {
  group('竖屏排布（底部胶囊 TabBar）', () {
    testWidgets('默认首页：底栏 + 六导航项 + 空态', (WidgetTester tester) async {
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      // 导航项单源（6 项）；「首页」同时出现在底栏标签与首页 AppBar 标题
      expect(find.text('首页'), findsNWidgets(2));
      expect(find.text('短剧'), findsOneWidget);
      expect(find.text('书架'), findsOneWidget);
      expect(find.text('远程源'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('备份'), findsOneWidget);
      // 首页内容（无站点 → 空态兜底）
      expect(find.textContaining('无可用站点'), findsOneWidget);
    });

    testWidgets('切到书架：收藏/历史 Tab + 空态', (WidgetTester tester) async {
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();

      expect(find.text('vbox 书架'), findsOneWidget);
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('历史'), findsOneWidget);
      expect(find.textContaining('暂无收藏'), findsOneWidget);
    });

    testWidgets('历史上 tab：空态引导', (WidgetTester tester) async {
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();

      expect(find.textContaining('暂无播放历史'), findsOneWidget);
    });
  });

  group('横屏排布（左侧 NavigationRail）', () {
    testWidgets('默认首页：侧栏 + 标签可见', (WidgetTester tester) async {
      await tester.pumpWidget(_shell(override: UiFormOverride.landscape));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('首页'), findsNWidgets(2));
      expect(find.text('书架'), findsOneWidget);
      expect(find.textContaining('无可用站点'), findsOneWidget);
    });

    testWidgets('切到远程源：页标题 + 侧栏标签并存', (WidgetTester tester) async {
      await tester.pumpWidget(_shell(override: UiFormOverride.landscape));
      await tester.pumpAndSettle();

      await tester.tap(find.text('远程源'));
      await tester.pumpAndSettle();

      // Rail label + RemoteSourcePage AppBar title
      expect(find.text('远程源'), findsNWidgets(2));
      expect(find.textContaining('未同步'), findsOneWidget);
      expect(find.textContaining('暂无订阅'), findsOneWidget);
    });

    testWidgets('远程源添加订阅：对话框输入后列表出现', (WidgetTester tester) async {
      await tester.pumpWidget(_shell(override: UiFormOverride.landscape));
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
      expect(
        find.textContaining('https://example.com/desktop.json'),
        findsOneWidget,
      );
    });

    testWidgets('切回书架：收藏仍可用', (WidgetTester tester) async {
      await tester.pumpWidget(_shell(override: UiFormOverride.landscape));
      await tester.pumpAndSettle();

      await tester.tap(find.text('远程源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();

      expect(find.text('vbox 书架'), findsOneWidget);
      expect(find.textContaining('暂无收藏'), findsOneWidget);
    });
  });

  group('共享内容（收藏 / 历史行为，双排布共用）', () {
    testWidgets('收藏列表：展示名称 / 来源 / 相对时间', (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(
          favorites: <FavoriteItem>[
            FavoriteItem(
              name: '测试影片',
              laiyuan: 'demo',
              detailurl: 'u/1',
              addedAt: TimeUtils.nowUnixSeconds(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();

      expect(find.text('测试影片'), findsOneWidget);
      expect(find.textContaining('demo'), findsOneWidget);
      expect(find.textContaining('刚刚'), findsOneWidget);
    });

    testWidgets('收藏移除：点击删除后回到空态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(
          favorites: <FavoriteItem>[
            FavoriteItem(
              id: 1,
              name: '待删除影片',
              detailurl: 'u/9',
              addedAt: TimeUtils.nowUnixSeconds(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      expect(find.text('待删除影片'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('待删除影片'), findsNothing);
      expect(find.textContaining('暂无收藏'), findsOneWidget);
    });

    testWidgets('收藏清空：确认框确认后列表清空', (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(
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
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      expect(find.text('片一'), findsOneWidget);

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('确定清空全部收藏？此操作不可撤销。'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();

      expect(find.text('片一'), findsNothing);
      expect(find.textContaining('暂无收藏'), findsOneWidget);
    });

    testWidgets('历史列表：展示集数 / 进度百分比 / 进度条', (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(
          history: <HistoryItem>[
            HistoryItem(
              name: '历史片',
              jishu: 3,
              detailurl: 'h/1',
              progress: 0.5,
              lastPlayedAt: TimeUtils.nowUnixSeconds(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('书架'));
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
  });

  group('输入模态：遥控（T.7 焦点遍历，不改版式）', () {
    testWidgets('遥控 → 焦点遍历组落地且版式仍为横屏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(override: UiFormOverride.landscape, isTv: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FocusTraversalGroup), findsWidgets);
      expect(find.byType(NavigationRail), findsOneWidget);
      // 十英尺缩放已接线（遥控模态端到端生效）。
      expect(find.byType(TenFootScaler), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });
  });
}