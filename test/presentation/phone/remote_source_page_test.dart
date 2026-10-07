/// 表现层 widget 测试：phone 形态远程源（清单状态卡 + 订阅管理）。
///
/// 直连 UseCase（D21 轻量路线），注入内存仓储 fakes 走真用例链路；
/// 覆盖空态 / 列表展示 / 添加（对话框）/ 重复地址拒绝 / 删除 / 清单刷新。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/result.dart';
import 'package:vbox/core/utils/time_utils.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/entities/remote_source/remote_source.dart';
import 'package:vbox/domain/entities/spider/spider.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/phone/remote_source_page.dart';
import 'package:vbox/presentation/ui_mode/ui_mode_resolver.dart';

import '../../support/fakes.dart';

/// 假内容浏览用例：源发现页数据（站点 / 推荐 / 分类内容）。
class _FakeContentBrowseUseCases extends ContentBrowseUseCases {
  _FakeContentBrowseUseCases({
    this.sites = const <SiteConfig>[],
    this.classes = const <VodCategory>[],
    this.recommended = const <VodItem>[],
  }) : super(
          loadAllSources: () async =>
              const Success<AllSourcesContainer>(AllSourcesContainer()),
        );

  final List<SiteConfig> sites;
  final List<VodCategory> classes;
  final List<VodItem> recommended;

  @override
  Future<Result<List<SiteConfig>>> listSites() async =>
      Success<List<SiteConfig>>(sites);

  @override
  Future<Result<HomeContentResult>> homeContent(String siteKey) async =>
      Success<HomeContentResult>(
        HomeContentResult(classes: classes, list: recommended),
      );
}

Widget _page({
  List<SubscriptionItem> subs = const <SubscriptionItem>[],
  InMemoryRemoteSourceRepository? remote,
  ContentBrowseUseCases? browse,
}) {
  return MultiProvider(
    providers: [
      Provider<SubscriptionUseCases>.value(
        value: SubscriptionUseCases(InMemorySubscriptionRepository(subs)),
      ),
      Provider<RemoteSourceUseCases>.value(
        value: RemoteSourceUseCases(
          remote ?? InMemoryRemoteSourceRepository(),
        ),
      ),
      ChangeNotifierProvider<UiFormController>.value(
        value: UiFormController(
          env: const UiFormEnv(override: UiFormOverride.portrait, hasTouch: true),
        ),
      ),
      Provider<ContentBrowseUseCases>.value(
        value: browse ?? buildContentBrowseUseCases(),
      ),
    ],
    child: const MaterialApp(home: RemoteSourcePage()),
  );
}

void main() {
  testWidgets('空订阅 + 清单 idle：显示引导与「未同步」', (WidgetTester tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无订阅'), findsOneWidget);
    expect(find.textContaining('未同步'), findsOneWidget);
  });

  testWidgets('订阅列表：展示名称 / 地址 / 从未同步', (WidgetTester tester) async {
    await tester.pumpWidget(_page(
      subs: <SubscriptionItem>[
        const SubscriptionItem(
          id: 1,
          dyname: '测试源',
          dyurl: 'https://example.com/sub.json',
          lastSyncAt: 0,
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('测试源'), findsOneWidget);
    expect(find.textContaining('https://example.com/sub.json'), findsOneWidget);
    expect(find.textContaining('从未同步'), findsOneWidget);
  });

  testWidgets('删除订阅：点击删除后回到空态', (WidgetTester tester) async {
    await tester.pumpWidget(_page(
      subs: <SubscriptionItem>[
        const SubscriptionItem(
          id: 1,
          dyname: '待删源',
          dyurl: 'https://example.com/x.json',
          lastSyncAt: 0,
        ),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('待删源'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('待删源'), findsNothing);
    expect(find.textContaining('暂无订阅'), findsOneWidget);
  });

  testWidgets('添加订阅：对话框输入后列表出现', (WidgetTester tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('订阅')); // FAB
    await tester.pumpAndSettle();
    expect(find.text('添加订阅'), findsOneWidget);

    // 页面另有「默认源地址」输入框，故按对话框范围定位其两个 TextField
    final Finder dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), '新订阅');
    await tester.enterText(
      dialogFields.at(1),
      'https://example.com/new.json',
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.text('新订阅'), findsOneWidget);
    expect(find.textContaining('https://example.com/new.json'), findsOneWidget);
    expect(find.textContaining('从未同步'), findsOneWidget);
  });

  testWidgets('添加重复地址：SnackBar 提示订阅已存在', (WidgetTester tester) async {
    await tester.pumpWidget(_page(
      subs: <SubscriptionItem>[
        const SubscriptionItem(
          id: 1,
          dyname: '已有源',
          dyurl: 'https://example.com/dup.json',
          lastSyncAt: 0,
        ),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('订阅'));
    await tester.pumpAndSettle();
    final Finder dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), '重复源');
    await tester.enterText(
      dialogFields.at(1),
      'https://example.com/dup.json',
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.textContaining('订阅已存在'), findsOneWidget);
    // 列表未新增
    expect(find.text('重复源'), findsNothing);
  });

  testWidgets('清单刷新：强制拉取并展示远程版本', (WidgetTester tester) async {
    final InMemoryRemoteSourceRepository remote = InMemoryRemoteSourceRepository()
      ..fetchResult = buildManifest();
    await tester.pumpWidget(_page(remote: remote));
    await tester.pumpAndSettle();

    // idle 态
    expect(find.textContaining('未同步'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(remote.fetchCount, 1);
    expect(find.textContaining('远程配置 2026.09.29.1'), findsOneWidget);
  });

  testWidgets('刷新失败：状态卡显示失败信息', (WidgetTester tester) async {
    final InMemoryRemoteSourceRepository remote = InMemoryRemoteSourceRepository();
    // 未设置 fetchResult → fake 返回 UnknownFailure
    await tester.pumpWidget(_page(remote: remote));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.textContaining('失败'), findsOneWidget);
    expect(remote.fetchCount, 1);
  });

  testWidgets('最近同步时间：非零 lastSyncAt 显示相对时间', (WidgetTester tester) async {
    await tester.pumpWidget(_page(
      subs: <SubscriptionItem>[
        SubscriptionItem(
          id: 1,
          dyname: '已同步源',
          dyurl: 'https://example.com/synced.json',
          lastSyncAt: TimeUtils.nowUnixSeconds(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('上次同步'), findsOneWidget);
    expect(find.textContaining('刚刚'), findsOneWidget);
  });

  testWidgets('远程源设置：开关 / 地址 / 清缓存 / 版本时间', (WidgetTester tester) async {
    final InMemoryRemoteSourceRepository remote = InMemoryRemoteSourceRepository()
      ..cached = buildManifest()
      ..cachedAt = 1700000000
      ..settingsValue = const RemoteSourceSettings(
        enabled: true,
        manifestUrl: 'https://example.com/m.json',
        lastConfigVersion: '2026.09.29.1',
        lastSyncTimeSeconds: 1700000000,
      );
    await tester.pumpWidget(_page(remote: remote));
    await tester.pumpAndSettle();

    // 对齐 iOS `SettingsViews` 远程源区块：开关 + 默认源地址 + 版本/时间信息行
    expect(find.text('启用远程默认源'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('默认源地址'), findsOneWidget);
    expect(find.text('https://example.com/m.json'), findsOneWidget);
    expect(find.textContaining('配置版本：2026.09.29.1'), findsOneWidget);
    expect(find.textContaining('同步时间：'), findsOneWidget);

    // 清缓存 → 触发仓储 clearCache，版本/时间回退为「无」
    await tester.tap(find.text('清缓存'));
    await tester.pumpAndSettle();
    expect(remote.clearCacheCount, 1);
    expect(find.textContaining('已清空远程源缓存'), findsOneWidget);
    expect(find.textContaining('配置版本：无'), findsOneWidget);
  });

  group('源发现标签', () {
    testWidgets('切到源发现：源栏 + 推荐 + 分类 + 海报', (WidgetTester tester) async {
      await tester.pumpWidget(_page(
        browse: _FakeContentBrowseUseCases(
          sites: <SiteConfig>[
            const SiteConfig(
              key: 's1',
              name: '站点1',
              type: 0,
              api: 'https://s1.example.com',
            ),
          ],
          classes: <VodCategory>[const VodCategory(typeId: '1', typeName: '电影')],
          recommended: <VodItem>[
            const VodItem(vodId: '1', vodName: '推荐片', vodPic: ''),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('源发现'));
      await tester.pumpAndSettle();

      expect(find.text('源'), findsOneWidget);
      expect(find.text('站点1'), findsOneWidget);
      expect(find.text('推荐'), findsOneWidget);
      expect(find.text('电影'), findsOneWidget);
      expect(find.text('推荐片'), findsOneWidget);
      // 源发现标签下不显示「订阅」FAB
      expect(find.text('订阅'), findsNothing);
    });

    testWidgets('源发现空态：无站点引导', (WidgetTester tester) async {
      await tester.pumpWidget(_page(browse: _FakeContentBrowseUseCases()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('源发现'));
      await tester.pumpAndSettle();

      expect(find.textContaining('无可用站点'), findsOneWidget);
    });
  });
}
