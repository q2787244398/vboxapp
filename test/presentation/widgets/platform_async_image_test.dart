/// 图片加载组件单测（批次 A · A-10）。
///
/// 验收：缓存（Flutter 内建 imageCache）/ 占位 / 失败态可用；平台封面分支
/// [PlatformAsyncImage.coverFor] URL 归一。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/presentation/theme/theme.dart';
import 'package:vbox/presentation/widgets/platform_async_image.dart';
import 'package:vbox/presentation/widgets/vbox/vbox.dart';

Widget _host(Widget child) => MaterialApp(
      theme: VboxTheme.build(skin: VboxSkin.light, brightness: Brightness.light),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('coverFor（平台封面分支）', () {
    test('null / 空白 → null（走占位态，不发请求）', () {
      expect(PlatformAsyncImage.coverFor(null), isNull);
      expect(PlatformAsyncImage.coverFor(''), isNull);
      expect(PlatformAsyncImage.coverFor('   '), isNull);
    });

    test('http:// 升迁 https://（防混合内容拦截）', () {
      expect(
        PlatformAsyncImage.coverFor('http://a.com/x.png'),
        'https://a.com/x.png',
      );
      expect(
        PlatformAsyncImage.coverFor('  http://a.com/x.png  '),
        'https://a.com/x.png',
      );
    });

    test('https / 其他协议原样透传', () {
      expect(
        PlatformAsyncImage.coverFor('https://a.com/x.png'),
        'https://a.com/x.png',
      );
      expect(
        PlatformAsyncImage.coverFor('data:image/png;base64,AAA'),
        'data:image/png;base64,AAA',
      );
    });
  });

  group('占位 / 失败态', () {
    testWidgets('URL 为 null：直接占位态（无 Image 节点）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            height: 180,
            child: PlatformAsyncImage(url: null),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('URL 为空串：占位态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            height: 180,
            child: PlatformAsyncImage(url: ''),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('网络加载失败：失败态兜底为占位', (WidgetTester tester) async {
      // flutter_test 默认拦截真实 HTTP（返回 400）→ errorBuilder 兜底。
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            height: 180,
            child: PlatformAsyncImage(url: 'https://example.com/nope.png'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('自定义占位组件生效', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            height: 180,
            child: PlatformAsyncImage(
              url: null,
              placeholder: Text('自定义占位'),
            ),
          ),
        ),
      );
      expect(find.text('自定义占位'), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsNothing);
    });
  });

  group('海报卡收敛（A-10 接线）', () {
    testWidgets('VboxPosterCard 占位态复用 PlatformAsyncImage', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            child: VboxPosterCard(title: '无封面'),
          ),
        ),
      );
      expect(find.byType(PlatformAsyncImage), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      expect(find.text('无封面'), findsOneWidget);
    });
  });
}