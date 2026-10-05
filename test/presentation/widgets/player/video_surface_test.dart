/// Wave A · R-渲1：视频输出面组件（Texture 承载 / 纵横比自适应 / 无纹理占位）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/presentation/theme/tokens/colors.dart';
import 'package:vbox/presentation/widgets/player/video_surface.dart';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: 400, height: 300, child: child),
    );

void main() {
  testWidgets('无纹理 → 深色占位（避免被误判为黑屏故障）', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const VideoSurface()));
    expect(find.byType(Texture), findsNothing);
    final ColoredBox box = tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(box.color, VboxColors.playerBackground);
  });

  testWidgets('有纹理 + 已知纵横比 → Texture 居中按比例', (WidgetTester tester) async {
    await tester.pumpWidget(
        _host(const VideoSurface(textureId: 7, aspectRatio: 16 / 9)));
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 7);
    final AspectRatio ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(ar.aspectRatio, closeTo(16 / 9, 1e-6));
  });

  testWidgets('有纹理 + 未知/非法纵横比 → 铺满（无 AspectRatio）', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const VideoSurface(textureId: 3, aspectRatio: 0)));
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 3);
    expect(find.byType(AspectRatio), findsNothing);
  });
}