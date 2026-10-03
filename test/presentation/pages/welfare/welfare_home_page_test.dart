/// 呈现层单测：福利专区首页（批次 H · H-06）。
///
/// 覆盖：三栏目 Tab + 平台网格（默认视频栏目）、栏目切换、空分类提示、失败态 + 重试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/domain/entities/welfare/welfare.dart';
import 'package:vbox/presentation/pages/welfare/welfare_home_page.dart';
import 'package:vbox/presentation/welfare/welfare_platform_controller.dart';

import '../../../support/fakes.dart';

Widget _page(WelfarePlatformController controller) =>
    ChangeNotifierProvider<WelfarePlatformController>.value(
      value: controller,
      child: const MaterialApp(home: WelfareHomePage()),
    );

WelfarePlatformController controllerWith({
  WelfarePlatformConfig? config,
}) =>
    WelfarePlatformController(
      datasource: InMemoryWelfarePlatformDatasource(config: config),
      cache: InMemoryWelfarePlatformCache(),
      prefs: PrefsManager.instance,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await PrefsManager.instance.init();
  });

  setUp(() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.clear();
  });

  testWidgets('三栏目 Tab 齐备，默认视频栏目显示其平台', (WidgetTester tester) async {
    await tester.pumpWidget(
      _page(controllerWith(config: buildWelfarePlatformConfig())),
    );
    await tester.pumpAndSettle();

    // 分段三栏。
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('直播'), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);

    // 默认视频栏目的平台可见，他栏不可见。
    expect(find.text('平台甲'), findsOneWidget);
    expect(find.text('平台乙'), findsOneWidget);
    expect(find.text('直播甲'), findsNothing);
    expect(find.text('漫画甲'), findsNothing);
  });

  testWidgets('切换栏目 → 仅显示该栏目平台', (WidgetTester tester) async {
    await tester.pumpWidget(
      _page(controllerWith(config: buildWelfarePlatformConfig())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('直播'));
    await tester.pumpAndSettle();

    expect(find.text('直播甲'), findsOneWidget);
    expect(find.text('平台甲'), findsNothing);

    await tester.tap(find.text('漫画'));
    await tester.pumpAndSettle();
    expect(find.text('漫画甲'), findsOneWidget);
    expect(find.text('直播甲'), findsNothing);
  });

  testWidgets('空分类 → 显示「此分类下暂无平台」', (WidgetTester tester) async {
    await tester.pumpWidget(
      _page(
        controllerWith(
          config: const WelfarePlatformConfig(
            meta: <String, Object?>{'version': 'x'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('此分类下暂无平台'), findsOneWidget);
  });

  testWidgets('拉取失败 → 显示错误消息与重试按钮', (WidgetTester tester) async {
    await tester.pumpWidget(_page(controllerWith()));
    await tester.pumpAndSettle();

    expect(find.text('fake 未配置福利平台数据'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}