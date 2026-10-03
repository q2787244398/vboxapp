/// 单一页树 + 全端统一底栏单测（批次 A · A-08 / A8 / A9）。
///
/// 覆盖：默认豆瓣首页（A9）、底栏 4 项（无福利）/ 门控 5 项（含福利）、
/// 枚举驱动内容区（福利增删不漂移）、全端底栏（横屏无 Rail）、
/// 个人中心宫格（I-01/I-02，工具入口迁入设置页）、设置页工具分区（I-03）、
/// 遥控模态焦点遍历（T.7）。
/// 形态以 [UiFormController] 的 override 强制（与真机视口解耦，判定分支可穷举）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/core/utils/time_utils.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/profile/session_controller.dart';
import 'package:vbox/presentation/shell/home_shell_page.dart';
import 'package:vbox/presentation/theme/vbox_skin_controller.dart';
import 'package:vbox/presentation/ui_mode/ui_mode_resolver.dart';
import 'package:vbox/presentation/welfare/welfare_controller.dart';
import 'package:vbox/presentation/welfare/welfare_platform_controller.dart';
import 'package:vbox/presentation/widgets/input/input.dart';
import 'package:vbox/presentation/widgets/vbox/vbox.dart';

import '../../support/fakes.dart';

Widget _shell({
  UiFormOverride override = UiFormOverride.portrait,
  bool isTv = false,
  bool welfareEnabled = true,
  bool welfareUnlocked = false,
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
      ChangeNotifierProvider<VboxSkinController>.value(
        value: VboxSkinController(),
      ),
      ChangeNotifierProvider<WelfareController>.value(
        value: WelfareController(
          enabled: welfareEnabled,
          unlocked: welfareUnlocked,
        ),
      ),
      ChangeNotifierProvider<SessionController>.value(
        value: SessionController(store: InMemorySettingsStore()),
      ),
      // H-01 / H-06：福利 Tab 落地页（门控）消费远程平台配置控制器；
      // 注入内存数据源，避免单测触网（默认返回失败 → 页面走错误态）。
      ChangeNotifierProvider<WelfarePlatformController>.value(
        value: WelfarePlatformController(
          datasource: InMemoryWelfarePlatformDatasource(),
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
      Provider<DoubanUseCases>.value(value: buildDoubanUseCases()),
    ],
    child: const MaterialApp(home: HomeShellPage()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 设置页（I-03）经 `PrefsManager.instance` 读契约键，测试需先注入内存偏好。
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await PrefsManager.instance.init();
  });

  group('全端底栏（悬浮胶囊 TabBar）+ 默认豆瓣首页（A8 / A9）', () {
    testWidgets('默认：4 项底栏（无福利）+ 豆瓣默认内容（无源不报错）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      // 全端统一悬浮胶囊底栏；不再使用 Material NavigationBar / 侧栏 Rail。
      expect(find.byType(VboxBottomNav), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);

      // 基础 4 项：首页 / 短剧 / 直播 / 我的（福利未解锁 → 隐藏）。
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('短剧'), findsOneWidget);
      expect(find.text('直播'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('福利'), findsNothing);

      // A9：首页默认内容为豆瓣（无可用源也不报错）。
      expect(find.text('豆瓣推荐'), findsOneWidget);
      expect(find.textContaining('豆瓣暂无内容'), findsOneWidget);
      expect(find.textContaining('无可用站点'), findsNothing);
    });

    testWidgets('门控开启（enabled && unlocked）：福利 Tab 在 index 3 出现',
        (WidgetTester tester) async {
      await tester.pumpWidget(_shell(welfareUnlocked: true));
      await tester.pumpAndSettle();

      expect(find.text('福利'), findsOneWidget);

      await tester.tap(find.text('福利'));
      await tester.pumpAndSettle();

      // 福利 Tab → 门控落地页。
      expect(find.text('福利专区'), findsOneWidget);
    });

    testWidgets('门控关闭（enabled=false）：福利 Tab 隐藏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(welfareEnabled: false, welfareUnlocked: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('福利'), findsNothing);
      expect(find.byType(VboxBottomNav), findsOneWidget);
    });

    testWidgets('切到「我的」：个人中心（未登录头部）+ 右上角设置入口',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();

      // I-01 / I-02：未登录头部（「未登录」+「点击登录」）+ 3×3 宫格。
      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('点击登录'), findsOneWidget);
      expect(find.text('观看记录'), findsOneWidget);
      expect(find.text('福利专区'), findsOneWidget);
      expect(find.text('我的收藏'), findsOneWidget);
      // 工具入口已迁入设置页 —— 个人中心不再出现「更多工具」/「书架」/「远程源」。
      expect(find.text('更多工具'), findsNothing);
      expect(find.text('书架'), findsNothing);
      expect(find.text('远程源'), findsNothing);
      // 右上角设置入口。
      expect(find.byIcon(Icons.settings), findsOneWidget);
      // 未登录不显示左上角退出按钮。
      expect(find.byIcon(Icons.logout), findsNothing);

      // 宫格入口「我的收藏」→ 收藏页。
      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无收藏'), findsOneWidget);
    });

    testWidgets('设置页（I-03）：工具 · 书架承载收藏 / 历史双 Tab（入口迁自个人中心）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();

      // 右上角齿轮 → 设置页。
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('皮肤'), findsOneWidget);
      expect(find.text('工具'), findsOneWidget);
      // 迁入设置页的四个工具入口。
      expect(find.text('书架'), findsOneWidget);
      expect(find.text('远程源'), findsOneWidget);
      expect(find.text('网盘管理'), findsOneWidget);
      expect(find.text('备份还原'), findsOneWidget);

      // 书架 → 收藏 / 历史双 Tab。
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('历史'), findsOneWidget);
      expect(find.textContaining('暂无收藏'), findsOneWidget);
    });

    testWidgets('横屏：仍为底栏（无侧栏 Rail / 顶栏）', (WidgetTester tester) async {
      await tester.pumpWidget(_shell(override: UiFormOverride.landscape));
      await tester.pumpAndSettle();

      expect(find.byType(VboxBottomNav), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.textContaining('豆瓣暂无内容'), findsOneWidget);
    });
  });

  group('内容单源（收藏 / 历史）', () {
    testWidgets('收藏列表：展示名称 / 来源 / 相对时间', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

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
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      // 工具入口已迁入设置页，经宫格「我的收藏」进入收藏列表。
      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();

      expect(find.text('测试影片'), findsOneWidget);
      expect(find.textContaining('demo'), findsOneWidget);
      expect(find.textContaining('刚刚'), findsOneWidget);
    });
  });

  group('输入模态：遥控（T.7 焦点遍历，不改版式）', () {
    testWidgets('遥控 → 焦点遍历组落地且版式仍为底栏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(override: UiFormOverride.landscape, isTv: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FocusTraversalGroup), findsWidgets);
      expect(find.byType(VboxBottomNav), findsOneWidget);
      // 十英尺缩放已接线（遥控模态端到端生效）。
      expect(find.byType(TenFootScaler), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });
  });
}