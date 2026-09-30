/// 表现层 widget 测试：phone 形态远程源（清单状态卡 + 订阅管理）。
///
/// 直连 UseCase（D21 轻量路线），注入内存仓储 fakes 走真用例链路；
/// 覆盖空态 / 列表展示 / 添加（对话框）/ 重复地址拒绝 / 删除 / 清单刷新。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/time_utils.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/phone/remote_source_page.dart';

import '../../support/fakes.dart';

Widget _page({
  List<SubscriptionItem> subs = const <SubscriptionItem>[],
  InMemoryRemoteSourceRepository? remote,
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

    await tester.enterText(find.byType(TextField).at(0), '新订阅');
    await tester.enterText(
      find.byType(TextField).at(1),
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
    await tester.enterText(find.byType(TextField).at(0), '重复源');
    await tester.enterText(
      find.byType(TextField).at(1),
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
}
