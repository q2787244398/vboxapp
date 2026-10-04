/// 设置页单测（批次 I · I-03 分区骨架 / I-04 显示模式 / I-05 更新入口）。
///
/// 唯一真相源：iOS `vbox/Views/SettingsViews.swift`
///   · L106-L134（`titleBar` + `settingsContent` 分区顺序）；
///   · L136-L173（`skinSettingsSection`）；L175-L220（`playbackSettingsSection`）。
///
/// 契约键经 [PrefsManager]（内存 mock）读写，隔离真实落盘。
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/data/datasources/local/subscribe_config_store.dart';
import 'package:vbox/data/datasources/local/tg_search_config_store.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/pages/diagnostics/site_diagnostics_page.dart';
import 'package:vbox/presentation/pages/settings/settings_page.dart';
import 'package:vbox/presentation/theme/vbox_skin_controller.dart';
import 'package:vbox/presentation/ui_mode/ui_mode.dart';
import 'package:vbox/presentation/widgets/vbox/vbox.dart';

import '../../../support/fakes.dart';

Widget _page(UiFormController form, {ContentBrowseUseCases? browse}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VboxSkinController>.value(
        value: VboxSkinController(),
      ),
      ChangeNotifierProvider<UiFormController>.value(value: form),
      // G-04：TG 搜索分区消费配置存储。
      ChangeNotifierProvider<TGSearchConfigStore>.value(
        value: TGSearchConfigStore(),
      ),
      // G-07：订阅配置分区消费订阅存储。
      ChangeNotifierProvider<SubscribeConfigStore>.value(
        value: SubscribeConfigStore(prefs: PrefsManager.instance),
      ),
      Provider<ContentBrowseUseCases>.value(
        value: browse ?? buildContentBrowseUseCases(),
      ),
      Provider<RemoteSourceUseCases>.value(
        value: RemoteSourceUseCases(InMemoryRemoteSourceRepository()),
      ),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

/// 取某标题所在设置行内的尾部开关。
Finder _switchInRow(String title) => find.descendant(
      of: find.ancestor(
        of: find.text(title),
        matching: find.byType(VboxSettingsRow),
      ),
      matching: find.byType(Switch),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final PrefsManager prefs = PrefsManager.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await prefs.init();
  });

  setUp(() async {
    await prefs.clearAll();
  });

  testWidgets('I-03：八大分区骨架齐备', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(UiFormController()));
    await tester.pumpAndSettle();

    expect(find.text('皮肤'), findsOneWidget);
    expect(find.text('显示模式'), findsWidgets); // 分区标题 + 行标题
    expect(find.text('播放设置'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
    // G-07：订阅配置分区 + 管理订阅源入口。
    expect(find.text('订阅配置'), findsOneWidget);
    expect(find.text('管理订阅源'), findsOneWidget);
    expect(find.text('站点诊断'), findsOneWidget); // G-08 分区标题
    expect(find.text('存储管理'), findsOneWidget);
    expect(find.text('日志调试'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    // 未实现域分区显式登记为「待实现」，不虚标可用。
    expect(find.text('更多设置（待实现）'), findsOneWidget);
    expect(find.text('TMDB 设置'), findsOneWidget);
    expect(find.text('站点管理'), findsOneWidget);
  });

  testWidgets('G-08：站点诊断入口展示接口总数并可进入诊断页', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ContentBrowseUseCases browse = buildContentBrowseUseCases(
      sites: <Map<String, Object?>>[
        siteJson(key: 'a', type: 0, api: 'https://a.example.com/api'),
        siteJson(key: 'b', type: 2),
      ],
    );
    await tester.pumpWidget(_page(UiFormController(), browse: browse));
    await tester.pumpAndSettle();

    // 入口行：标题「接口状态检测」+ 尾部「共 N 个接口」。
    expect(find.text('接口状态检测'), findsOneWidget);
    expect(find.text('共 2 个接口'), findsOneWidget);

    await tester.tap(find.text('接口状态检测'));
    await tester.pumpAndSettle();
    expect(find.byType(SiteDiagnosticsPage), findsOneWidget);
    expect(find.text('接口状态诊断'), findsOneWidget);
    // 诊断页启动后回填远程源信息行。
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('I-03：工具分区承接个人中心迁出的四个入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(UiFormController()));
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsOneWidget);
    expect(find.text('远程源'), findsOneWidget);
    expect(find.text('网盘管理'), findsOneWidget);
    expect(find.text('备份还原'), findsOneWidget);
  });

  testWidgets('I-03：皮肤四选 + 跟随系统开关存在', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(UiFormController()));
    await tester.pumpAndSettle();

    expect(find.byType(VboxSkinPicker), findsOneWidget);
    expect(find.text('黑暗/浅色跟随手机外观'), findsOneWidget);
    expect(_switchInRow('黑暗/浅色跟随手机外观'), findsOneWidget);
  });

  testWidgets('I-04：选择显示模式 → 写入 app_ui_form_override 并热切换',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final UiFormController form = UiFormController();
    await tester.pumpWidget(_page(form));
    await tester.pumpAndSettle();
    expect(form.override, UiFormOverride.auto);

    await tester.tap(find.text('当前：自动'));
    await tester.pumpAndSettle();
    // 对话框列出三档（自动 / 手机竖屏 / 大屏横屏）。
    expect(find.text('手机（竖屏）'), findsOneWidget);
    expect(find.text('大屏（横屏）'), findsOneWidget);

    await tester.tap(find.text('手机（竖屏）'));
    await tester.pumpAndSettle();

    expect(form.override, UiFormOverride.portrait);
    expect(await prefs.getString('app_ui_form_override'), 'portrait');
    expect(find.text('当前：手机（竖屏）'), findsOneWidget);
    // 切换成功后的 VboxToast 会挂 2s 自动关闭 Timer，需排空以免 teardown 断言失败。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('I-03：自定义弹幕源开关 → 写入契约键并展开地址输入行',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(UiFormController()));
    await tester.pumpAndSettle();

    // 关闭态：无输入行。
    expect(find.byType(VboxSettingsInputRow), findsNothing);

    await tester.tap(_switchInRow('自定义弹幕源'));
    await tester.pumpAndSettle();

    expect(await prefs.getBool('custom_danmaku_source_enabled'), isTrue);
    expect(find.byType(VboxSettingsInputRow), findsOneWidget);
  });

  testWidgets('I-05：关于分区展示版本号 + 检查更新入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(UiFormController()));
    await tester.pumpAndSettle();

    expect(find.text('版本'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });
}