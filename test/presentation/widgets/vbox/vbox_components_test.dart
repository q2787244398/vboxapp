/// 表现层组件库单测（批次 A · A-04）。
///
/// 规格对齐 `docs/UI对齐基准_v1.0.md` §2.3 / §2.4 / §2.5：
///   ① Card 圆角 20 + 渐变描边 + 可选主色阴影
///   ② Chip 选中填充 `#34C759`，未选中取分组底
///   ③ SectionHeader 标题 + 右侧操作
///   ④ EpisodeChip 当前项 `#2196F3` 文字 + 20% 底 + 描边
///   ⑤ Button 三形态（primary / secondary / danger）
///   ⑥ Toast 黑 85% + 白字 + 自动消失
///   ⑦ Dialog 标题 + 操作
///   ⑧ PosterCard 占位态 + 标题
///   ⑨ SourceBadge 分类色固定映射
///   ⑩ BottomNav / NavRail 渲染
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/presentation/theme/theme.dart';
import 'package:vbox/presentation/widgets/vbox/vbox.dart';

Widget _host(Widget child) => MaterialApp(
      theme: VboxTheme.build(skin: VboxSkin.light, brightness: Brightness.light),
      home: Scaffold(body: Center(child: child)),
    );

Material _materialUnder(WidgetTester tester, Type owner) => tester.widget<Material>(
      find.descendant(of: find.byType(owner), matching: find.byType(Material)).first,
    );

void main() {
  group('VboxCard', () {
    testWidgets('渲染子组件并应用渐变描边装饰', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const VboxCard(child: Text('内容'))));
      expect(find.text('内容'), findsOneWidget);

      final DecoratedBox box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(VboxCard),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final BoxDecoration deco = box.decoration as BoxDecoration;
      expect(deco.gradient, isA<LinearGradient>());
      expect(deco.borderRadius, VboxRadii.panel);
    });

    testWidgets('onTap 生效', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _host(VboxCard(onTap: () => taps++, child: const Text('点击'))),
      );
      await tester.tap(find.text('点击'));
      expect(taps, 1);
    });
  });

  group('VboxChip', () {
    testWidgets('选中填充固定胶囊色', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const VboxChip(label: '榜单', selected: true)));
      expect(_materialUnder(tester, VboxChip).color, VboxColors.chipSelected);
    });

    testWidgets('未选中取分组底色', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const VboxChip(label: '分类')));
      final BuildContext ctx = tester.element(find.byType(VboxChip));
      final ColorScheme scheme = Theme.of(ctx).colorScheme;
      expect(_materialUnder(tester, VboxChip).color, scheme.surfaceContainerHighest);
    });
  });

  group('VboxSectionHeader', () {
    testWidgets('渲染标题并可触发查看全部', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _host(VboxSectionHeader(title: '热播', onSeeAll: () => taps++)),
      );
      expect(find.text('热播'), findsOneWidget);
      await tester.tap(find.text('查看全部'));
      expect(taps, 1);
    });
  });

  group('VboxEpisodeChip', () {
    testWidgets('当前项用强调色文字与 20% 底色', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(const VboxEpisodeChip(label: '第 1 集', selected: true)),
      );
      final Text text = tester.widget<Text>(find.text('第 1 集'));
      expect(text.style?.color, VboxColors.selected);
      expect(
        _materialUnder(tester, VboxEpisodeChip).color,
        VboxColors.selected.withValues(alpha: 0.20),
      );
    });
  });

  group('VboxButton', () {
    testWidgets('primary 用主色实心', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const VboxButton(label: '播放')));
      final BuildContext ctx = tester.element(find.byType(VboxButton));
      expect(
        _materialUnder(tester, VboxButton).color,
        Theme.of(ctx).colorScheme.primary,
      );
    });

    testWidgets('danger 用红字 + 红底 10%', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(VboxButton(
          label: '删除',
          kind: VboxButtonKind.danger,
          onPressed: () {},
        )),
      );
      expect(
        _materialUnder(tester, VboxButton).color,
        VboxColors.danger.withValues(alpha: 0.10),
      );
      final Text text = tester.widget<Text>(find.text('删除'));
      expect(text.style?.color, VboxColors.danger);
    });

    testWidgets('禁用态透明 50%', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const VboxButton(label: '不可用')));
      final Opacity opacity = tester.widget<Opacity>(
        find
            .descendant(of: find.byType(VboxButton), matching: find.byType(Opacity))
            .first,
      );
      expect(opacity.opacity, 0.5);
    });
  });

  group('VboxToast', () {
    testWidgets('展示后自动消失', (WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: VboxTheme.build(skin: VboxSkin.light, brightness: Brightness.light),
          home: Builder(
            builder: (BuildContext c) {
              ctx = c;
              return const Scaffold();
            },
          ),
        ),
      );
      VboxToast.show(ctx, '已收藏', duration: const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('已收藏'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('已收藏'), findsNothing);
    });
  });

  group('VboxDialog', () {
    testWidgets('弹出并显示标题与内容', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VboxTheme.build(skin: VboxSkin.light, brightness: Brightness.light),
          home: Builder(
            builder: (BuildContext c) => Scaffold(
              body: Center(
                child: VboxButton(
                  label: '打开',
                  onPressed: () => VboxDialog.show<void>(
                    c,
                    title: '提示',
                    child: const Text('正文'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('提示'), findsOneWidget);
      expect(find.text('正文'), findsOneWidget);
    });
  });

  group('VboxPosterCard', () {
    testWidgets('无封面时展示占位并保留标题', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const VboxPosterCard(title: '片名')));
      expect(find.text('片名'), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('评分标签展示', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(const VboxPosterCard(title: '片名', rating: '9.1')),
      );
      expect(find.text('9.1'), findsOneWidget);
    });
  });

  group('VboxSourceBadge', () {
    testWidgets('按分类固定色板取色', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(const VboxSourceBadge.category(
          label: '蜘蛛',
          category: VboxCategory.spider,
        )),
      );
      final Text text = tester.widget<Text>(find.text('蜘蛛'));
      expect(text.style?.color, VboxColors.categoryColors[VboxCategory.spider]);
    });
  });

  group('导航组件', () {
    const List<VboxNavItem> items = <VboxNavItem>[
      VboxNavItem(icon: Icons.home_outlined, label: '首页'),
      VboxNavItem(icon: Icons.search, label: '搜索'),
    ];

    testWidgets('BottomNav 渲染项并可切换', (WidgetTester tester) async {
      int index = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: VboxTheme.build(skin: VboxSkin.light, brightness: Brightness.light),
          home: Scaffold(
            bottomNavigationBar: VboxBottomNav(
              items: items,
              selectedIndex: index,
              onSelected: (int i) => index = i,
            ),
          ),
        ),
      );
      expect(find.text('首页'), findsOneWidget);
      await tester.tap(find.text('搜索'));
      expect(index, 1);
    });

    testWidgets('NavRail 渲染项', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VboxTheme.build(skin: VboxSkin.light, brightness: Brightness.light),
          home: Scaffold(
            body: Row(
              children: <Widget>[
                VboxNavRail(
                  items: items,
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(VboxNavRail), findsOneWidget);
    });
  });
}