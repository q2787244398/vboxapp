/// 品牌闪屏单测（批次 L · L-壳1）。
///
/// 关键回归点：品牌字体（VboxBrand）自然字标宽度（≈217.6pt）大于 iOS 聚合宽度
/// 182.2pt，字标必须等比缩至贴合，**不得出现 RenderFlex 溢出**。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/presentation/widgets/brand/vbox_splash_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 加载品牌字体真实度量（缺省测试字体为 Ahem，无法暴露宽度溢出）。
    final FontLoader loader = FontLoader('VboxBrand')
      ..addFont(rootBundle.load('assets/fonts/VboxBrand-Bold.otf'));
    await loader.load();
  });

  testWidgets('品牌闪屏渲染无溢出（品牌字体真实度量）', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: VboxSplashView()));

    // 推进至字母聚合 / swoosh / 发光 / 呼吸循环各阶段。
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    // 卸载以释放循环动画 Ticker 与内部定时器。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}