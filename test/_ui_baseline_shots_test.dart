// 临时脚本：生成「UI 对齐基准」样式图（生成后即删除，不进入仓库）。
//
// 用途：把 iOS 侧实测采样的设计令牌与页面骨架，渲染成可核对的 PNG 样式图。
// 说明：字体用 Noto Sans CJK（简中）+ MaterialIcons，保证中文与图标真实可读；
//       网络图片不可用，海报一律用渐变占位。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _outDir = '/workspace/ui_baseline_out';

// ── iOS 实测令牌（见 docs/UI对齐基准_v1.0.md §2）─────────────────────────
const Color kClassic = Color(0xFFE11D48); // 经典（light）主色
const Color kFrosted = Color(0xFF7C3AED); // 磨砂（frosted）主色
const Color kLiquid = Color(0xFF38BDF8); // 液态（liquid）主色
const Color kAccentAsset = Color(0xFF191919); // Assets AccentColor
const Color kActive = Color(0xFF2196F3); // 播放器选中项
const Color kGreen = Color(0xFF34C759); // 胶囊选中
const Color kPlayerBg = Color(0xFF0F0F23); // 播放器深底
const Color kBlue1 = Color(0xFF3B82F6);
const Color kBlue2 = Color(0xFF2563EB);
const Color kBlue3 = Color(0xFF1D4ED8);
const List<Color> kLogPalette = <Color>[
  Color(0xFF6B7280), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF3B82F6),
  Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFF6366F1), Color(0xFFEC4899),
  Color(0xFFF97316), Color(0xFF14B8A6),
];

// iOS 系统语义色（Apple HIG 标准值，源码以 Color(uiColor:) 引用）
const Color kSysBgLight = Color(0xFFFFFFFF);
const Color kSysBgDark = Color(0xFF000000);
const Color kSysBg2Light = Color(0xFFF2F2F7);
const Color kSysBg2Dark = Color(0xFF1C1C1E);
const Color kSysLabelDark = Color(0xFFFFFFFF);
const Color kSysLabel2Light = Color(0x993C3C43);

const String kFamily = 'NotoSansSC';

Future<void> _loadFont(String family, List<String> paths) async {
  final FontLoader loader = FontLoader(family);
  for (final String p in paths) {
    loader.addFont(
      File(p).readAsBytes().then((List<int> b) => ByteData.view(Uint8List.fromList(b).buffer)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont(kFamily, <String>[
      '/usr/share/fonts/opentype/noto-cjk-otf/NotoSansCJKsc-Regular.otf',
      '/usr/share/fonts/opentype/noto-cjk-otf/NotoSansCJKsc-Bold.otf',
    ]);
    await _loadFont('MaterialIcons', <String>[
      '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    // ignore: avoid_print
    print('FONT loaded kFamily=$kFamily exists=${File('/usr/share/fonts/opentype/noto-cjk-otf/NotoSansCJKsc-Regular.otf').lengthSync()}');
    Directory(_outDir).createSync(recursive: true);
  });

  Future<void> shoot(WidgetTester tester, String name, Size size, Widget child) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: kFamily, colorSchemeSeed: kClassic),
      home: RepaintBoundary(key: key, child: child),
    ));
    await tester.pumpAndSettle();
    final Uint8List? bytes = await tester.runAsync(() async {
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 2.0);
      final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return d!.buffer.asUint8List();
    });
    File('$_outDir/$name.png').writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('OK $name.png');
  }

  testWidgets('01 tokens', (WidgetTester t) => shoot(t, '01_tokens', const Size(1180, 992), _tokens()));
  testWidgets('02 phone home', (WidgetTester t) => shoot(t, '02_phone_home', const Size(390, 844), _phoneHome()));
  testWidgets('03 phone search', (WidgetTester t) => shoot(t, '03_phone_search', const Size(390, 844), _phoneSearch()));
  testWidgets('04 phone detail', (WidgetTester t) => shoot(t, '04_phone_detail', const Size(390, 844), _phoneDetail()));
  testWidgets('05 phone player', (WidgetTester t) => shoot(t, '05_phone_player', const Size(390, 844), _phonePlayer()));
  testWidgets('06 phone profile', (WidgetTester t) => shoot(t, '06_phone_profile', const Size(390, 844), _phoneProfile()));
  testWidgets('07 desktop home', (WidgetTester t) => shoot(t, '07_desktop_home', const Size(1280, 800), _desktopHome()));
  testWidgets('08 tv home', (WidgetTester t) => shoot(t, '08_tv_home', const Size(960, 540), _tvHome()));
}

// ══════════════════════════════════════════════════════════════════════════
// 通用组件
// ══════════════════════════════════════════════════════════════════════════

TextStyle _ts(double size, FontWeight w, Color c) => TextStyle(
    fontFamily: kFamily,
    fontFamilyFallback: const <String>[kFamily, 'Roboto'],
    fontSize: size,
    fontWeight: w,
    color: c,
    height: 1.25);

Widget _statusBar(Color fg, {double pad = 20}) => SizedBox(
      height: 46,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Row(children: <Widget>[
          Text('9:41', style: _ts(14, FontWeight.w700, fg)),
          const Spacer(),
          Icon(Icons.signal_cellular_alt, size: 15, color: fg),
          const SizedBox(width: 5),
          Icon(Icons.wifi, size: 15, color: fg),
          const SizedBox(width: 5),
          Icon(Icons.battery_full, size: 16, color: fg),
        ]),
      ),
    );

/// 海报占位（2:3），用渐变替代网络图。
Widget _poster(String title, {String? score, double w = 104, String? corner}) {
  return SizedBox(
    width: w,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Stack(children: <Widget>[
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF374151), Color(0xFF111827)],
              ),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.movie_creation_outlined, size: 22, color: Colors.white.withValues(alpha: 0.25)),
          ),
        ),
        if (score != null)
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(score, style: _ts(10, FontWeight.w700, const Color(0xFFFFC107))),
            ),
          ),
        if (corner != null)
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: kClassic, borderRadius: BorderRadius.circular(4)),
              child: Text(corner, style: _ts(9, FontWeight.w700, Colors.white)),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(12, FontWeight.w500, const Color(0xFF111827))),
    ]),
  );
}

Widget _pill(String text, {bool on = false, Color onColor = kClassic}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: on ? onColor : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(16),
        border: on ? Border.all(color: onColor) : null,
      ),
      child: Text(text, style: _ts(13, on ? FontWeight.w600 : FontWeight.w400, on ? Colors.white : const Color(0xFF4B5563))),
    );

Widget _sectionHeader(String title, {String? more, Color color = kClassic}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: <Widget>[
        Container(width: 3, height: 15, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(title, style: _ts(16, FontWeight.w700, const Color(0xFF111827))),
        const Spacer(),
        if (more != null) Text(more, style: _ts(12, FontWeight.w400, const Color(0xFF9CA3AF))),
        if (more != null) const Icon(Icons.chevron_right, size: 15, color: Color(0xFF9CA3AF)),
      ]),
    );

Widget _tabBar(Color active) {
  const List<(IconData, String)> items = <(IconData, String)>[
    (Icons.home_filled, '首页'),
    (Icons.search, '搜索'),
    (Icons.video_library_outlined, '短剧'),
    (Icons.live_tv_outlined, '直播'),
    (Icons.person_outline, '我的'),
  ];
  return Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items
          .map(((IconData, String) e) => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(e.$1, size: 22, color: e.$2 == '首页' ? active : const Color(0xFF9CA3AF)),
                const SizedBox(height: 2),
                Text(e.$2, style: _ts(10, e.$2 == '首页' ? FontWeight.w700 : FontWeight.w400, e.$2 == '首页' ? active : const Color(0xFF9CA3AF))),
              ]))
          .toList(),
    ),
  );
}

Widget _settingRow(IconData icon, String label, {String? value, Color tint = kBlue1}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: <Widget>[
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: tint),
        ),
        const SizedBox(width: 12),
        Text(label, style: _ts(15, FontWeight.w400, const Color(0xFF111827))),
        const Spacer(),
        if (value != null) Text(value, style: _ts(13, FontWeight.w400, const Color(0xFF9CA3AF))),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, size: 17, color: Color(0xFFC4C9D1)),
      ]),
    );

// ══════════════════════════════════════════════════════════════════════════
// 01 设计令牌总览
// ══════════════════════════════════════════════════════════════════════════

Widget _swatch(String name, String hex, Color c, {double w = 150}) {
  final bool light = ThemeData.estimateBrightnessForColor(c) == Brightness.light;
  final Color fg = light ? const Color(0xFF111827) : Colors.white;
  return Container(
    width: w,
    height: 62,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x22000000)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Text(name, style: _ts(11, FontWeight.w600, fg.withValues(alpha: 0.92))),
        Text(hex, style: _ts(10, FontWeight.w400, fg.withValues(alpha: 0.7))),
      ],
    ),
  );
}

Widget _tokens() {
  Widget block(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: _ts(15, FontWeight.w700, const Color(0xFF111827))),
          const SizedBox(height: 10),
          child,
        ]),
      );

  return Container(
    color: const Color(0xFFF7F8FA),
    padding: const EdgeInsets.all(28),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text('vbox · UI 对齐基准 · 设计令牌', style: _ts(26, FontWeight.w700, const Color(0xFF111827))),
      const SizedBox(height: 4),
      Text('右侧色值均来自 iOS 源码实测（vbox/App/AppSettings.swift + 各视图）；系统语义色为 Apple HIG 标准值',
          style: _ts(12, FontWeight.w400, const Color(0xFF6B7280))),
      const SizedBox(height: 20),
      block('① 皮肤主色（四套皮肤，pref 键 app_skin_mode，默认 light）', Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
        _swatch('黑暗 dark / 浅色 light', '#E11D48', kClassic, w: 196),
        _swatch('磨砂 frosted', '#7C3AED', kFrosted),
        _swatch('液态 liquid', '#38BDF8', kLiquid),
        _swatch('AccentColor 资产', '#191919', kAccentAsset),
      ])),
      block('② 语义色', Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
        _swatch('选中 / 激活', '#2196F3', kActive),
        _swatch('选中胶囊', '#34C759', kGreen),
        _swatch('播放器深底', '#0F0F23', kPlayerBg),
        _swatch('系统底 浅', '#FFFFFF', kSysBgLight),
        _swatch('系统分组底 浅', '#F2F2F7', kSysBg2Light),
        _swatch('系统分组底 深', '#1C1C1E', kSysBg2Dark),
      ])),
      block('③ 品牌蓝渐变（我的页头部）', Container(
        height: 56, width: 420,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: <Color>[kBlue1, kBlue2, kBlue3]),
          boxShadow: <BoxShadow>[BoxShadow(color: kBlue1.withValues(alpha: 0.40), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        alignment: Alignment.center,
        child: Text('#3B82F6 → #2563EB → #1D4ED8   shadow r16 y6 @40%', style: _ts(12, FontWeight.w600, Colors.white)),
      )),
      block('④ 分类色板（日志 / 站点标签，10 色）', Row(
        children: kLogPalette
            .map((Color c) => Padding(padding: const EdgeInsets.only(right: 8), child: Container(width: 62, height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)))))
            .toList(),
      )),
      block('⑤ 字阶（.font(.system(size:))）', Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
        for (final int s in <int>[10, 11, 12, 13, 14, 15, 16, 18, 24, 28])
          Padding(padding: const EdgeInsets.only(right: 22), child: Text('$s', style: _ts(s.toDouble(), FontWeight.w600, const Color(0xFF111827)))),
      ])),
      block('⑥ 圆角档位（cornerRadius，continuous）', Row(children: <Widget>[
        for (final int r in <int>[4, 6, 8, 10, 12, 14, 16, 20])
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(children: <Widget>[
              Container(width: 54, height: 54, decoration: BoxDecoration(color: kClassic.withValues(alpha: 0.14), border: Border.all(color: kClassic), borderRadius: BorderRadius.circular(r.toDouble()))),
              const SizedBox(height: 5),
              Text('$r', style: _ts(11, FontWeight.w500, const Color(0xFF4B5563))),
            ]),
          ),
      ])),
      block('⑦ 关键组件：卡片（r20 + 1px 渐变描边 10%→0%）', SizedBox(
        width: 300, height: 84,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x1A000000)),
          ),
          child: Center(child: Text('卡片 / 面板', style: _ts(15, FontWeight.w600, const Color(0xFF111827)))),
        ),
      )),
      block('⑧ 关键组件：Toast（黑 85% · r12）', Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
        child: Text('已复制到剪贴板', style: _ts(13, FontWeight.w500, Colors.white)),
      )),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════
// 02 手机首页
// ══════════════════════════════════════════════════════════════════════════

Widget _phoneHome() {
  return Container(
    color: kSysBg2Light,
    child: Column(children: <Widget>[
      ColoredBox(color: kSysBgLight, child: _statusBar(const Color(0xFF111827))),
      Expanded(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            // 顶栏：个人中心 / 源选择 / 搜索
            Container(
              color: kSysBgLight,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(children: <Widget>[
                const Icon(Icons.person_outline, size: 24, color: Color(0xFF374151)),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(color: kClassic.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(17), border: Border.all(color: kClassic.withValues(alpha: 0.35))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                      const Icon(Icons.movie_filter_outlined, size: 15, color: kClassic),
                      const SizedBox(width: 5),
                      Text('默认源 · 索尼影视', style: _ts(13, FontWeight.w600, kClassic)),
                      const Icon(Icons.keyboard_arrow_down, size: 16, color: kClassic),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.history, size: 24, color: Color(0xFF374151)),
              ]),
            ),
            // 搜索栏
            Container(
              color: kSysBgLight,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                height: 38,
                decoration: BoxDecoration(color: kSysBg2Light, borderRadius: BorderRadius.circular(19)),
                child: Row(children: <Widget>[
                  const SizedBox(width: 14),
                  const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 8),
                  Text('搜索影视 / 演员 / 导演', style: _ts(14, FontWeight.w400, const Color(0xFF9CA3AF))),
                ]),
              ),
            ),
            // 轮播
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Stack(children: <Widget>[
                Container(
                  height: 168,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFF4C1D95), Color(0xFF831843)]),
                  ),
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
                    Text('繁花', style: _ts(22, FontWeight.w700, Colors.white)),
                    const SizedBox(height: 2),
                    Text('王家卫 · 全 30 集 · 豆瓣 8.7', style: _ts(12, FontWeight.w400, Colors.white.withValues(alpha: 0.85))),
                  ]),
                ),
                Positioned(
                  right: 12, top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
                    child: Text('1 / 6', style: _ts(11, FontWeight.w600, Colors.white)),
                  ),
                ),
              ]),
            ),
            // 分类胶囊
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  _pill('电影', on: true),
                  const SizedBox(width: 8),
                  _pill('电视剧'), const SizedBox(width: 8),
                  _pill('综艺'), const SizedBox(width: 8),
                  _pill('动漫'), const SizedBox(width: 8),
                  _pill('纪录片'), const SizedBox(width: 8),
                  _pill('短剧'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 横向列表 1
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _sectionHeader('豆瓣热门', more: '更多'),
            ),
            SizedBox(
              height: 190,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  _poster('繁花', score: '8.7'), const SizedBox(width: 12),
                  _poster('漫长的季节', score: '9.4'), const SizedBox(width: 12),
                  _poster('三体', score: '8.7'), const SizedBox(width: 12),
                  _poster('狂飙', score: '8.5'), const SizedBox(width: 12),
                  _poster('莲花楼', score: '8.1'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 横向列表 2：宽卡
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _sectionHeader('最近更新'),
            ),
            SizedBox(
              height: 146,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  _wideCard('繁花', '更新至 30 集', kClassic),
                  const SizedBox(width: 12),
                  _wideCard('庆余年 2', '更新至 36 集', kClassic),
                  const SizedBox(width: 12),
                  _wideCard('墨雨云间', '全 40 集', kClassic),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      // MiniPlayerBar + 悬浮 TabBar
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: kClassic, borderRadius: BorderRadius.circular(14)),
        child: Row(children: <Widget>[
          const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text('繁花 · 第 3 集', style: _ts(12, FontWeight.w600, Colors.white)),
          const Spacer(),
          const Icon(Icons.close, size: 16, color: Colors.white70),
        ]),
      ),
      const SizedBox(height: 6),
      _tabBar(kClassic),
    ]),
  );
}

Widget _wideCard(String title, String sub, Color accent) => Container(
      width: 190,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Container(
          height: 92,
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFF334155), Color(0xFF0F172A)])),
          alignment: Alignment.center,
          child: Icon(Icons.play_circle_outline, size: 26, color: Colors.white.withValues(alpha: 0.45)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(13, FontWeight.w600, const Color(0xFF111827))),
            Text(sub, style: _ts(10, FontWeight.w400, const Color(0xFF9CA3AF))),
          ]),
        ),
      ]),
    );

// ══════════════════════════════════════════════════════════════════════════
// 03 手机搜索
// ══════════════════════════════════════════════════════════════════════════

Widget _phoneSearch() {
  const List<String> history = <String>['繁花', '三体', '狂飙', '王家卫', '悬疑', '豆瓣 9 分'];
  return Container(
    color: kSysBg2Light,
    child: Column(children: <Widget>[
      ColoredBox(color: kSysBgLight, child: _statusBar(const Color(0xFF111827))),
      Container(
        color: kSysBgLight,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: Row(children: <Widget>[
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(color: kSysBg2Light, borderRadius: BorderRadius.circular(19)),
              child: Row(children: <Widget>[
                const SizedBox(width: 13),
                const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 8),
                Text('繁', style: _ts(14, FontWeight.w400, const Color(0xFF111827))),
                const Spacer(),
                const Icon(Icons.cancel, size: 17, color: Color(0xFFC4C9D1)),
                const SizedBox(width: 12),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Text('搜索', style: _ts(15, FontWeight.w600, kClassic)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: <Widget>[
          // 排行榜入口
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: <Color>[kBlue1, kBlue2, kBlue3]),
            ),
            child: Row(children: <Widget>[
              const Icon(Icons.emoji_events_outlined, size: 26, color: Colors.white),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('豆瓣排行榜', style: _ts(15, FontWeight.w700, Colors.white)),
                Text('实时热榜 · 电影 / 剧集 / 综艺', style: _ts(11, FontWeight.w400, Colors.white.withValues(alpha: 0.85))),
              ]),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 20, color: Colors.white),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: <Widget>[
            Text('搜索历史', style: _ts(15, FontWeight.w700, const Color(0xFF111827))),
            const Spacer(),
            const Icon(Icons.delete_outline, size: 17, color: Color(0xFF9CA3AF)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: history.map((String h) => _pill(h)).toList()),
          const SizedBox(height: 22),
          Text('搜索结果 · 共 128 条', style: _ts(15, FontWeight.w700, const Color(0xFF111827))),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 14, children: <Widget>[
            _poster('繁花', score: '8.7', w: 104),
            _poster('繁花似锦', score: '6.2', w: 104),
            _poster('繁花 番外', score: '7.5', w: 104),
            _poster('似锦繁花', score: '5.8', w: 104),
            _poster('繁花落尽', score: '7.0', w: 104),
            _poster('繁花如梦', score: '6.6', w: 104),
          ]),
        ]),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════
// 04 手机详情页
// ══════════════════════════════════════════════════════════════════════════

Widget _phoneDetail() {
  return Container(
    color: kSysBg2Light,
    child: Stack(children: <Widget>[
      Column(children: <Widget>[
        // 头图
        SizedBox(
          height: 250,
          child: Stack(children: <Widget>[
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF4C1D95), Color(0xFF831843)]),
              ),
            ),
            Positioned(
              left: 0, right: 0, top: 0,
              child: _statusBar(Colors.white, pad: 16),
            ),
            Positioned(
              left: 12, top: 48,
              child: Row(children: <Widget>[
                _glassIcon(Icons.arrow_back_ios_new),
                const SizedBox(width: 8),
                _glassIcon(Icons.bookmark_border),
              ]),
            ),
            Positioned(
              right: 12, top: 48,
              child: Row(children: <Widget>[
                _glassIcon(Icons.ios_share),
                const SizedBox(width: 8),
                _glassIcon(Icons.cast),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: Container(
            color: kSysBg2Light,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: <Widget>[
              Text('繁花', style: _ts(24, FontWeight.w700, const Color(0xFF111827))),
              const SizedBox(height: 4),
              Text('2023 · 中国大陆 · 剧情 / 年代', style: _ts(12, FontWeight.w400, const Color(0xFF6B7280))),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFC107)),
                const SizedBox(width: 3),
                Text('8.7', style: _ts(15, FontWeight.w700, const Color(0xFF111827))),
                const SizedBox(width: 12),
                _tag('4K'), const SizedBox(width: 6), _tag('国语'), const SizedBox(width: 6), _tag('完结'),
              ]),
              const SizedBox(height: 12),
              Text('九十年代的上海，阿宝凭借改革开放的春风成为商界后起之秀……',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: _ts(13, FontWeight.w400, const Color(0xFF4B5563))),
              const SizedBox(height: 4),
              Text('展开', style: _ts(13, FontWeight.w600, kClassic)),
              const SizedBox(height: 18),
              _sectionHeader('选集', more: '共 30 集'),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                for (int i = 1; i <= 15; i++)
                  Container(
                    width: 44, height: 36,
                    decoration: BoxDecoration(
                      color: i == 3 ? kClassic : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: i == 3 ? kClassic : const Color(0xFFE5E7EB)),
                    ),
                    alignment: Alignment.center,
                    child: Text('$i', style: _ts(13, FontWeight.w600, i == 3 ? Colors.white : const Color(0xFF374151))),
                  ),
              ]),
              const SizedBox(height: 20),
              _sectionHeader('播放源', more: '3 个可用'),
              Wrap(spacing: 8, children: <Widget>[
                _pill('默认源', on: true),
                _pill('线路 2'),
                _pill('线路 3'),
              ]),
            ]),
          ),
        ),
      ]),
      // 底部操作条
      Positioned(
        left: 0, right: 0, bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
          child: Row(children: <Widget>[
            Container(
              width: 108, height: 46,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: kClassic, width: 1.4)),
              alignment: Alignment.center,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                const Icon(Icons.bookmark_border, size: 17, color: kClassic),
                const SizedBox(width: 5),
                Text('收藏', style: _ts(14, FontWeight.w600, kClassic)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 46,
                decoration: BoxDecoration(color: kClassic, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                  const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('立即播放 · 第 3 集', style: _ts(15, FontWeight.w700, Colors.white)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ]),
  );
}

Widget _glassIcon(IconData icon) => Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.32), shape: BoxShape.circle),
      child: Icon(icon, size: 15, color: Colors.white),
    );

Widget _tag(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)),
      child: Text(t, style: _ts(10, FontWeight.w500, const Color(0xFF4B5563))),
    );

// ══════════════════════════════════════════════════════════════════════════
// 05 手机播放器
// ══════════════════════════════════════════════════════════════════════════

Widget _phonePlayer() {
  return Container(
    color: kPlayerBg,
    child: Column(children: <Widget>[
      // 顶栏
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 44, 12, 8),
        child: Row(children: <Widget>[
          const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('繁花', style: _ts(15, FontWeight.w700, Colors.white)),
            Text('第 3 集 · 默认源', style: _ts(11, FontWeight.w400, Colors.white.withValues(alpha: 0.6))),
          ]),
          const Spacer(),
          const Icon(Icons.cast, size: 19, color: Colors.white),
          const SizedBox(width: 16),
          const Icon(Icons.more_horiz, size: 19, color: Colors.white),
        ]),
      ),
      // 视频区
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFF1F2937), Color(0xFF0B1120)]),
          ),
          child: Center(
            child: Container(
              width: 62, height: 62,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.14)),
              child: const Icon(Icons.play_arrow_rounded, size: 38, color: Colors.white),
            ),
          ),
        ),
      ),
      // 控制层
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(children: <Widget>[
          Stack(children: <Widget>[
            Container(height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(2))),
            FractionallySizedBox(
              widthFactor: 0.38,
              child: Container(height: 3, decoration: BoxDecoration(color: kClassic, borderRadius: BorderRadius.circular(2))),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            Text('12:04', style: _ts(11, FontWeight.w500, Colors.white.withValues(alpha: 0.75))),
            const Spacer(),
            Text('31:40', style: _ts(11, FontWeight.w500, Colors.white.withValues(alpha: 0.75))),
          ]),
        ]),
      ),
      // 功能按钮行
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _ctrl(Icons.skip_previous_rounded, '上一集'),
            _ctrl(Icons.play_arrow_rounded, '播放', big: true),
            _ctrl(Icons.skip_next_rounded, '下一集'),
            _ctrl(Icons.speed, '1.0x'),
            _ctrl(Icons.closed_caption_outlined, '字幕'),
            _ctrl(Icons.list_rounded, '选集', active: true),
            _ctrl(Icons.fullscreen, '全屏'),
          ],
        ),
      ),
      // 选集抽屉（半屏，当前项 #2196F3）
      const SizedBox(height: 12),
      Container(
        height: 226,
        decoration: const BoxDecoration(color: Color(0xFF111827), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Text('选集', style: _ts(14, FontWeight.w700, Colors.white)),
            const SizedBox(width: 8),
            Text('共 30 集', style: _ts(11, FontWeight.w400, Colors.white.withValues(alpha: 0.55))),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.25,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (int i = 1; i <= 18; i++)
                  Container(
                    decoration: BoxDecoration(
                      color: i == 3 ? kActive.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                      border: i == 3 ? Border.all(color: kActive) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text('$i', style: _ts(12, FontWeight.w600, i == 3 ? kActive : Colors.white.withValues(alpha: 0.82))),
                  ),
              ],
            ),
          ),
        ]),
      ),
    ]),
  );
}

Widget _ctrl(IconData icon, String label, {bool big = false, bool active = false}) => Column(children: <Widget>[
      Icon(icon, size: big ? 34 : 20, color: active ? kClassic : Colors.white),
      const SizedBox(height: 3),
      Text(label, style: _ts(9, FontWeight.w500, active ? kClassic : Colors.white.withValues(alpha: 0.72))),
    ]);

// ══════════════════════════════════════════════════════════════════════════
// 06 手机我的
// ══════════════════════════════════════════════════════════════════════════

Widget _phoneProfile() {
  Widget group(List<Widget> rows) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      );

  return Container(
    color: kSysBg2Light,
    child: Column(children: <Widget>[
      ColoredBox(color: Colors.white, child: _statusBar(const Color(0xFF111827))),
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: <Widget>[
          // 头部渐变卡
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[kBlue1, kBlue2, kBlue3]),
              boxShadow: <BoxShadow>[BoxShadow(color: kBlue1.withValues(alpha: 0.38), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(children: <Widget>[
              Row(children: <Widget>[
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.22), border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 2)),
                  child: const Icon(Icons.person, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('未登录', style: _ts(17, FontWeight.w700, Colors.white)),
                  const SizedBox(height: 2),
                  Text('点击登录 · 同步收藏与历史', style: _ts(11, FontWeight.w400, Colors.white.withValues(alpha: 0.85))),
                ]),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 20, color: Colors.white),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[
                _stat('128', '收藏'), _stat('46', '历史'), _stat('12', '订阅源'),
              ]),
            ]),
          ),
          // 分组 1
          group(<Widget>[
            _settingRow(Icons.dns_outlined, '播放源管理', value: '3 个'),
            const Divider(height: 1, indent: 56),
            _settingRow(Icons.emoji_events_outlined, '豆瓣榜单'),
            const Divider(height: 1, indent: 56),
            _settingRow(Icons.live_tv_outlined, '直播源管理', value: '2 个'),
            const Divider(height: 1, indent: 56),
            _settingRow(Icons.cloud_outlined, '网盘管理'),
          ]),
          // 分组 2
          group(<Widget>[
            _settingRow(Icons.backup_outlined, '备份与恢复', tint: kGreen),
            const Divider(height: 1, indent: 56),
            _settingRow(Icons.description_outlined, '日志查看', tint: kGreen),
            const Divider(height: 1, indent: 56),
            _settingRow(Icons.troubleshoot, '站点诊断', tint: kGreen),
            const Divider(height: 1, indent: 56),
            _settingRow(Icons.brush_outlined, '皮肤', value: '经典', tint: kFrosted),
            const Divider(height: 1, indent: 56),
            _settingRow(Icons.info_outline, '关于', value: 'v1.0.0', tint: kGreen),
          ]),
          // 皮肤选择器
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('皮肤（app_skin_mode）', style: _ts(14, FontWeight.w700, const Color(0xFF111827))),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                _skinChip('经典', kClassic, on: true),
                const SizedBox(width: 10),
                _skinChip('磨砂', kFrosted),
                const SizedBox(width: 10),
                _skinChip('液态', kLiquid),
              ]),
            ]),
          ),
        ]),
      ),
      _tabBar(kClassic),
    ]),
  );
}

Widget _stat(String n, String label) => Column(children: <Widget>[
      Text(n, style: _ts(20, FontWeight.w700, Colors.white)),
      const SizedBox(height: 1),
      Text(label, style: _ts(11, FontWeight.w400, Colors.white.withValues(alpha: 0.85))),
    ]);

Widget _skinChip(String label, Color c, {bool on = false}) => Expanded(
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: on ? c.withValues(alpha: 0.12) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? c : Colors.transparent, width: 1.4),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(label, style: _ts(13, FontWeight.w600, on ? c : const Color(0xFF6B7280))),
        ]),
      ),
    );

// ══════════════════════════════════════════════════════════════════════════
// 07 桌面端首页
// ══════════════════════════════════════════════════════════════════════════

Widget _desktopHome() {
  return Container(
    color: const Color(0xFFF7F8FA),
    child: Row(children: <Widget>[
      // NavigationRail
      Container(
        width: 84,
        color: Colors.white,
        child: Column(children: <Widget>[
          const SizedBox(height: 18),
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: kClassic, borderRadius: BorderRadius.circular(11)),
            alignment: Alignment.center,
            child: Text('V', style: _ts(20, FontWeight.w700, Colors.white)),
          ),
          const SizedBox(height: 22),
          _rail(Icons.home_filled, '首页', on: true),
          _rail(Icons.search, '搜索'),
          _rail(Icons.live_tv_outlined, '直播'),
          _rail(Icons.bookmark_border, '收藏'),
          _rail(Icons.history, '历史'),
          const Spacer(),
          _rail(Icons.settings_outlined, '设置'),
          const SizedBox(height: 18),
        ]),
      ),
      // 主区
      Expanded(
        child: Column(children: <Widget>[
          Container(
            height: 68,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: <Widget>[
              Container(
                width: 340, height: 38,
                decoration: BoxDecoration(color: kSysBg2Light, borderRadius: BorderRadius.circular(19)),
                child: Row(children: <Widget>[
                  const SizedBox(width: 14),
                  const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 8),
                  Text('搜索影视 / 演员 / 导演', style: _ts(13, FontWeight.w400, const Color(0xFF9CA3AF))),
                ]),
              ),
              const SizedBox(width: 16),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: kClassic.withValues(alpha: 0.4)), color: kClassic.withValues(alpha: 0.06)),
                child: Row(children: <Widget>[
                  Text('默认源 · 索尼影视', style: _ts(12, FontWeight.w600, kClassic)),
                  const Icon(Icons.keyboard_arrow_down, size: 15, color: kClassic),
                ]),
              ),
              const Spacer(),
              const Icon(Icons.notifications_none, size: 20, color: Color(0xFF6B7280)),
              const SizedBox(width: 16),
              Container(width: 32, height: 32, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE5E7EB)), child: const Icon(Icons.person, size: 18, color: Color(0xFF6B7280))),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 18, 24, 18), children: <Widget>[
              Row(children: <Widget>[
                _pill('电影', on: true), const SizedBox(width: 8),
                _pill('电视剧'), const SizedBox(width: 8),
                _pill('综艺'), const SizedBox(width: 8),
                _pill('动漫'), const SizedBox(width: 8),
                _pill('纪录片'),
              ]),
              const SizedBox(height: 20),
              _sectionHeader('豆瓣热门', more: '更多'),
              Wrap(spacing: 18, runSpacing: 18, children: <Widget>[
                _poster('繁花', score: '8.7', w: 138, corner: '4K'),
                _poster('漫长的季节', score: '9.4', w: 138),
                _poster('三体', score: '8.7', w: 138, corner: '新'),
                _poster('狂飙', score: '8.5', w: 138),
                _poster('莲花楼', score: '8.1', w: 138),
                _poster('庆余年 2', score: '8.0', w: 138, corner: '热'),
              ]),
            ]),
          ),
        ]),
      ),
    ]),
  );
}

Widget _rail(IconData icon, String label, {bool on = false}) => Container(
      width: 60,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(color: on ? kClassic.withValues(alpha: 0.10) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: Column(children: <Widget>[
        Icon(icon, size: 21, color: on ? kClassic : const Color(0xFF9CA3AF)),
        const SizedBox(height: 2),
        Text(label, style: _ts(10, on ? FontWeight.w700 : FontWeight.w400, on ? kClassic : const Color(0xFF9CA3AF))),
      ]),
    );

// ══════════════════════════════════════════════════════════════════════════
// 08 TV 首页
// ══════════════════════════════════════════════════════════════════════════

Widget _tvHome() {
  const List<String> tabs = <String>['首页', '搜索', '直播', '短剧', '我的'];
  return Container(
    color: const Color(0xFF0B0F1A),
    child: Column(children: <Widget>[
      // 顶栏
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 10),
        child: Row(children: <Widget>[
          Text('VBOX', style: _ts(19, FontWeight.w700, Colors.white)),
          const SizedBox(width: 30),
          for (final String s in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 26),
              child: Column(children: <Widget>[
                Text(s, style: _ts(15, s == '首页' ? FontWeight.w700 : FontWeight.w400, s == '首页' ? Colors.white : Colors.white.withValues(alpha: 0.45))),
                const SizedBox(height: 4),
                Container(width: 22, height: 3, decoration: BoxDecoration(color: s == '首页' ? kClassic : Colors.transparent, borderRadius: BorderRadius.circular(2))),
              ]),
            ),
          const Spacer(),
          Text('20:41', style: _ts(13, FontWeight.w500, Colors.white.withValues(alpha: 0.6))),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Container(width: 3, height: 16, decoration: BoxDecoration(color: kClassic, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('豆瓣热门', style: _ts(17, FontWeight.w700, Colors.white)),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 178,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  _tvCard('繁花', '8.7', focused: false),
                  const SizedBox(width: 16),
                  _tvCard('漫长的季节', '9.4', focused: true),
                  const SizedBox(width: 16),
                  _tvCard('三体', '8.7', focused: false),
                  const SizedBox(width: 16),
                  _tvCard('狂飙', '8.5', focused: false),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(children: <Widget>[
              Container(width: 3, height: 16, decoration: BoxDecoration(color: kClassic, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('最近更新', style: _ts(17, FontWeight.w700, Colors.white)),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final String t in <String>['庆余年 2', '墨雨云间', '玫瑰的故事', '狐妖小红娘'])
                    Container(
                      width: 190, height: 92,
                      margin: const EdgeInsets.only(right: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFF1E293B), Color(0xFF0B1120)]),
                      ),
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(10),
                      child: Text(t, style: _ts(13, FontWeight.w600, Colors.white.withValues(alpha: 0.9))),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
      // 底部遥控提示
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 18),
        child: Row(children: <Widget>[
          _hint('← →', '切换'),
          const SizedBox(width: 22),
          _hint('●', '确认'),
          const SizedBox(width: 22),
          _hint('↺', '返回'),
          const Spacer(),
          Text('焦点态：主色描边 + 放大 4% + 阴影', style: _ts(11, FontWeight.w400, Colors.white.withValues(alpha: 0.42))),
        ]),
      ),
    ]),
  );
}

Widget _tvCard(String title, String score, {required bool focused}) => Transform.scale(
      scale: focused ? 1.04 : 1.0,
      child: Container(
        width: 158,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: focused ? 0.10 : 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: focused ? kClassic : Colors.transparent, width: 2),
          boxShadow: focused ? <BoxShadow>[BoxShadow(color: kClassic.withValues(alpha: 0.45), blurRadius: 18)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(
            child: Stack(children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFF334155), Color(0xFF0F172A)]),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.movie_creation_outlined, size: 26, color: Colors.white.withValues(alpha: 0.3)),
              ),
              Positioned(right: 5, bottom: 5, child: Text(score, style: _ts(11, FontWeight.w700, const Color(0xFFFFC107)))),
            ]),
          ),
          const SizedBox(height: 7),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(13, FontWeight.w600, Colors.white)),
        ]),
      ),
    );

Widget _hint(String key, String label) => Row(children: <Widget>[
      Text(key, style: _ts(12, FontWeight.w700, Colors.white.withValues(alpha: 0.75))),
      const SizedBox(width: 6),
      Text(label, style: _ts(12, FontWeight.w400, Colors.white.withValues(alpha: 0.45))),
    ]);