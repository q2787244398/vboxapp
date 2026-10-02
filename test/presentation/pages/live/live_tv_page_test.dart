/// 直播页 Widget 测试（批次 E · E-01）。
///
/// 对齐 iOS `LiveTVView` 的 UI 结构：频道源胶囊 / 分类胶囊 / 双列频道卡。
/// 通过注入预加载 [LiveTvController]（MockClient 返回 M3U，无真实网络）验证
/// 首帧与交互，不依赖 Flutter 本地环境之外的资源。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vbox/core/network/http_client.dart';
import 'package:vbox/presentation/pages/live/live_tv_controller.dart';
import 'package:vbox/presentation/pages/live/live_tv_page.dart';

const String _m3u = '#EXTM3U\n'
    '#EXTINF:-1 tvg-logo="http://logo/1.png" group-title="News",CCTV-1\n'
    'http://stream/cctv1.m3u8\n'
    '#EXTINF:-1 group-title="News",CCTV-2\n'
    'http://stream/cctv2.m3u8\n'
    '#EXTINF:-1 group-title="Sports",CCTV-5\n'
    'http://stream/cctv5.m3u8\n';

LiveTvController _loadedController() => LiveTvController(
      client: HttpClient(
        inner: MockClient((http.Request _) async => http.Response(_m3u, 200)),
      ),
    );

Future<LiveTvController> _preload(WidgetTester tester) async {
  final LiveTvController controller = _loadedController();
  addTearDown(controller.dispose);
  await controller.fetchSubscribeChannels('http://example.com/tv.m3u');
  await tester.pumpWidget(MaterialApp(home: LiveTVPage(controller: controller)));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('渲染频道源胶囊 + 分类胶囊 + 双列频道卡', (WidgetTester tester) async {
    await _preload(tester);

    // 频道源胶囊：当前源展示名。
    expect(find.text('默认源1 (秒播)'), findsOneWidget);

    // 分类胶囊：动态分组。
    expect(find.text('News'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);

    // 默认选中首分类 News → 双列频道卡。
    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('CCTV-2'), findsOneWidget);
    expect(find.text('1条线路'), findsNWidgets(2));
    expect(find.text('CCTV-5'), findsNothing);
  });

  testWidgets('切换分类胶囊，频道卡随分组更新', (WidgetTester tester) async {
    await _preload(tester);

    await tester.tap(find.text('Sports'));
    await tester.pumpAndSettle();

    expect(find.text('CCTV-5'), findsOneWidget);
    expect(find.text('CCTV-1'), findsNothing);
  });

  testWidgets('点击频道源胶囊弹出切换源浮层', (WidgetTester tester) async {
    await _preload(tester);

    await tester.tap(find.text('默认源1 (秒播)'));
    await tester.pumpAndSettle();

    // 浮层标题 + 全部可用源（默认2个）。
    expect(find.text('选择直播源 2'), findsOneWidget);
    expect(find.text('默认源2 (运营商IPTV)'), findsOneWidget);
  });

  testWidgets('订阅源为空时展示空态提示', (WidgetTester tester) async {
    final LiveTvController controller = LiveTvController(
      client: HttpClient(
        inner: MockClient((http.Request _) async => http.Response('', 200)),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(home: LiveTVPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无频道'), findsOneWidget);
    expect(find.text('默认源1 (秒播)'), findsOneWidget);
  });
}