/// 网盘文件列表页 Widget 单测（批次 F · F-07）。
///
/// 对齐基准（唯一真相源）：iOS 播放链「多文件列表 + 转存 + 清理队列」面
/// （`vbox/Services/CloudDriveManager.swift`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/data/datasources/local/cloud_drive_cleanup_queue_store.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/domain/entities/cloud/cloud_drive.dart';
import 'package:vbox/domain/entities/cloud/cloud_drive_files.dart';
import 'package:vbox/domain/entities/cloud/node_pan.dart';
import 'package:vbox/platform/player/pan_player.dart';
import 'package:vbox/presentation/pages/cloud/files.dart';
import 'package:vbox/presentation/pages/cloud/files_controller.dart';

/// 假网盘播放编排：仅覆盖分享解析（C-盘2）。
class _FakePanPlayer extends PanPlayer {
  _FakePanPlayer(this.share);

  final NodePanShare share;
  int resolveCalls = 0;

  @override
  Future<NodePanShare> resolveShare(CloudDriveType type, String shareUrl) async {
    resolveCalls++;
    return share;
  }
}

/// 内存目录列举替身（parentId → 条目）。
class _FakeLister implements CloudDriveFileLister {
  _FakeLister(this.tree);

  final Map<String, List<CloudDriveFileEntry>> tree;
  final List<String> calls = <String>[];

  @override
  Future<List<CloudDriveFileEntry>> list({
    required CloudDriveType drive,
    required String parentId,
  }) async {
    calls.add(parentId);
    return List<CloudDriveFileEntry>.of(
      tree[parentId] ?? const <CloudDriveFileEntry>[],
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required CloudDriveFileLister lister,
  required CloudDriveCleanupQueueStore store,
  CloudDriveType drive = CloudDriveType.quark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CloudDriveFilesPage(
        driveType: drive,
        lister: lister,
        cleanupStore: store,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final PrefsManager pm = PrefsManager.instance;
  late CloudDriveCleanupQueueStore store;
  late _FakeLister lister;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await pm.init();
  });

  setUp(() async {
    await pm.clearAll();
    store = CloudDriveCleanupQueueStore(pm);
    lister = _FakeLister(<String, List<CloudDriveFileEntry>>{
      '': <CloudDriveFileEntry>[
        const CloudDriveFileEntry(fileId: 'dir_1', name: '季风剧场', isFolder: true),
        const CloudDriveFileEntry(fileId: 'v_1', name: 'EP01.mp4', size: 2048),
      ],
      'dir_1': <CloudDriveFileEntry>[
        const CloudDriveFileEntry(fileId: 'v_2', name: 'EP02.mkv', size: 1048576),
      ],
    });
  });

  testWidgets('顶栏 + 面包屑 + 文件夹优先条目列表', (WidgetTester tester) async {
    await _pump(tester, lister: lister, store: store);

    expect(find.text('夸克网盘 文件列表'), findsOneWidget);
    expect(find.text('夸克网盘'), findsOneWidget);
    // 文件夹在前（compareTo 排序）。
    expect(find.text('季风剧场'), findsOneWidget);
    expect(find.text('EP01.mp4'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(lister.calls, <String>['']);
  });

  testWidgets('点击文件夹进入子目录并更新面包屑', (WidgetTester tester) async {
    await _pump(tester, lister: lister, store: store);

    await tester.tap(find.text('季风剧场'));
    await tester.pumpAndSettle();

    expect(lister.calls, <String>['', 'dir_1']);
    expect(find.text('夸克网盘 / 季风剧场'), findsOneWidget);
    expect(find.text('EP02.mkv'), findsOneWidget);
  });

  testWidgets('点击文件转存入清理队列；重复点击命中去重', (WidgetTester tester) async {
    await _pump(tester, lister: lister, store: store);

    expect(find.text('暂无待清理项'), findsOneWidget);

    await tester.tap(find.text('EP01.mp4'));
    await tester.pumpAndSettle();
    expect(await store.count(), 1);
    expect(find.text('待清理 1 项'), findsOneWidget);

    await tester.tap(find.text('EP01.mp4'));
    await tester.pumpAndSettle();
    // 去重：仍只有 1 条，并提示已在队列中。
    expect(await store.count(), 1);
    expect(find.text('该文件已在清理队列中'), findsOneWidget);

    // 放掉 VboxToast 的 2s 自动关闭定时器，避免 teardown 报 pending timer。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('未到期时「立即清理」提示无可清理项', (WidgetTester tester) async {
    await _pump(tester, lister: lister, store: store);

    await tester.tap(find.text('EP01.mp4'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('cloud_cleanup_now')));
    await tester.pumpAndSettle();

    expect(await store.count(), 1);
    expect(find.text('暂无可清理项（未到期）'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('已到期条目「立即清理」移除并清空队列', (WidgetTester tester) async {
    await store.enqueue(
      drive: CloudDriveType.quark.id,
      tokenName: '',
      fileIds: <String>['v_1'],
      delay: Duration.zero,
      now: DateTime.now().subtract(const Duration(minutes: 5)),
    );

    await _pump(tester, lister: lister, store: store);
    expect(find.text('待清理 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('cloud_cleanup_now')));
    await tester.pumpAndSettle();

    expect(await store.count(), 0);
    expect(find.text('已清理 1 项'), findsOneWidget);
    expect(find.text('暂无待清理项'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('空目录展示占位文案', (WidgetTester tester) async {
    await _pump(
      tester,
      lister: _FakeLister(<String, List<CloudDriveFileEntry>>{}),
      store: store,
    );
    expect(find.text('当前目录没有文件'), findsOneWidget);
  });

  testWidgets('列举器缺省未接入时报错文案', (WidgetTester tester) async {
    final CloudDriveFilesController controller = CloudDriveFilesController(
      driveType: CloudDriveType.quark,
      cleanupStore: store,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudDriveFilesPage(
          driveType: CloudDriveType.quark,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未接入'), findsOneWidget);
  });

  test('分享模式：resolveShare → 文件条目 + 标题（C-盘2）', () async {
    final _FakePanPlayer pan = _FakePanPlayer(
      const NodePanShare(title: '季风剧场', entries: <NodePanEntry>[
        NodePanEntry(playID: 'p1', name: 'EP01.mp4'),
        NodePanEntry(playID: 'p2', name: 'EP02.mp4'),
      ]),
    );
    final CloudDriveFilesController c = CloudDriveFilesController(
      driveType: CloudDriveType.one15,
      cleanupStore: store,
      shareUrl: 'https://share/abc',
      panPlayer: pan,
    );
    await c.load();

    expect(c.isShareMode, isTrue);
    expect(c.title, '季风剧场');
    expect(c.breadcrumb, '季风剧场');
    expect(c.entries.map((CloudDriveFileEntry e) => e.name).toList(),
        <String>['EP01.mp4', 'EP02.mp4']);
    expect(await c.goUp(), isFalse); // 分享模式无目录层级
    expect(pan.resolveCalls, 1);
  });

  test('分享模式：未注入 PanPlayer → 报错文案', () async {
    final CloudDriveFilesController c = CloudDriveFilesController(
      driveType: CloudDriveType.one15,
      cleanupStore: store,
      shareUrl: 'https://share/abc',
    );
    await c.load();
    expect(c.error, contains('尚未接入'));
    expect(c.entries, isEmpty);
  });

  testWidgets('分享模式页面：渲染条目 + 隐藏清理队列卡', (WidgetTester tester) async {
    final _FakePanPlayer pan = _FakePanPlayer(
      const NodePanShare(title: '季风剧场', entries: <NodePanEntry>[
        NodePanEntry(playID: 'p1', name: 'EP01.mp4'),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudDriveFilesPage(
          driveType: CloudDriveType.one15,
          shareUrl: 'https://share/abc',
          panPlayer: pan,
          cleanupStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('季风剧场'), findsOneWidget);
    expect(find.text('EP01.mp4'), findsOneWidget);
    expect(find.text('清理队列'), findsNothing);
    expect(find.text('当前目录没有文件'), findsNothing);
  });
}
