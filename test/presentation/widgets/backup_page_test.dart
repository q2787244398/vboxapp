/// 表现层 widget 测试：#B4 —— 备份 / 还原页。
///
/// 注入真实 [BackupService]（ffi 真库 + 临时 StoragePaths），覆盖：
///   ① 导出 Tab：9 个类目 + 敏感类目锁标记 + 导出按钮
///   ② 导入 Tab：无文件空态 / 有文件列表
///   ③ 还原参数对话框：冲突策略 + 类目
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbox/core/storage/storage_paths.dart';
import 'package:vbox/data/datasources/local/backup_manager.dart';
import 'package:vbox/data/datasources/local/backup_service.dart';
import 'package:vbox/presentation/widgets/backup_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BackupService svc;
  late Directory backupDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final Directory tmp = await Directory.systemTemp.createTemp('vbox_backup_ui');
    StoragePaths.configure(tmp.path);
    await StoragePaths.ensureLayout();
    backupDir = Directory(StoragePaths.backupDir);
    svc = BackupService();
  });

  setUp(() async {
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }
    await backupDir.create(recursive: true);
  });

  Widget app() => MaterialApp(home: BackupPage(service: svc));

  testWidgets('导出 Tab：9 个类目 + 敏感锁标记 + 导出按钮', (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    for (final BackupCategory c in BackupCategory.values) {
      expect(find.text(c.label), findsOneWidget, reason: c.name);
    }
    expect(find.byIcon(Icons.lock_outline), findsOneWidget); // 仅网盘凭据
    expect(find.widgetWithText(FilledButton, '导出备份'), findsOneWidget);
  });

  testWidgets('导入 Tab：无备份文件 → 空态', (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入还原'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无备份文件'), findsOneWidget);
  });

  testWidgets('导入 Tab：列出 .vboxbak 文件并可打开还原对话框', (WidgetTester tester) async {
    await svc.writeBackupFile('{"schemaVersion":1}');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入还原'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expect(find.textContaining('.vboxbak'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.archive_outlined));
    await tester.pumpAndSettle();

    expect(find.text('还原备份'), findsOneWidget);
    expect(find.text('合并（保留本机，补齐备份）'), findsOneWidget);
    expect(find.text('覆盖（清空本机后写入）'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始还原'), findsOneWidget);
  });
}