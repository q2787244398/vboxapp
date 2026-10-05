/// 表现层：品牌启动页（批次 L · L-壳1）。
///
/// 唯一真相源：iOS `VboxSplashView.swift`
/// （`vbox/Views/VboxSplashView.swift`）+ `ContentView.swift` L11-L15/L149-L190
/// （最短展示 3.5s · 数据门控 · 10s 兜底）。
///
/// 对齐口径：
///  - 深浅自适应渐变背景（浅 `0.97/0.90` 灰阶 · 深 `0.12/0.05` 灰阶，取 iOS 同值）；
///  - 品牌字标四字母**四角飞入聚合**（V 左上 / b 左下 / o 右上 / x 右下，
///    位移 500×(1,0.7)、旋转 ±30/±25、错峰 0/0.08/0.14/0.20s）；
///  - swoosh 托底（从左向右扫入，0.30s 延时 · 0.55s easeOut · 顺时针 4°）；
///  - 聚合后发光（0.7s）→ 呼吸缩放（2.4s，1.05×）+ 上下浮动（3.0s，±6pt）无限循环；
///  - 底部两行小字 + 版本号（发光后淡入）。
///
/// 落地差异（如实登记）：iOS 用 5 张 PNG（`splash_letter_V/b/o/x` + `splash_swoosh`）
/// 精确重叠装配；Flutter 侧无同源 PNG，改用品牌字体 [VboxBrand.fontFamily] 渲染
/// 「V 大 box 小」字标 + 品牌蓝渐变圆条替代 swoosh，动画时序与位移/旋转参数保持一致。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../theme/brand.dart';
import '../../theme/tokens/colors.dart';

/// 启动页渐变底色（深浅自适应；启动图与品牌闪屏共用同一取值）。
List<Color> vboxSplashGradient(Brightness brightness) => brightness == Brightness.dark
    ? const <Color>[Color.fromRGBO(31, 31, 41, 1), Color.fromRGBO(13, 13, 18, 1)]
    : const <Color>[Color.fromRGBO(247, 247, 250, 1), Color.fromRGBO(230, 230, 237, 1)];

/// 静态品牌底色（对齐 iOS 原生启动图角色：依赖加载期铺满品牌渐变，杜绝白屏）。
///
/// 与 [VboxSplashView] 同色，故「静态底色 → 品牌闪屏」过渡无跳色。
class VboxSplashBackdrop extends StatelessWidget {
  /// 构造。
  const VboxSplashBackdrop({super.key, this.brightness});

  /// 指定明暗；缺省取运行环境平台亮度（此时尚未完成皮肤加载）。
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final Brightness b = brightness ??
        MediaQuery.maybePlatformBrightnessOf(context) ??
        Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: vboxSplashGradient(b),
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// 飞入方向（对齐 iOS `LetterFlyDirection`）。
enum _FlyDirection {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  /// 位移（距离 500，纵向 ×0.7）。
  Offset get offset => switch (this) {
        _FlyDirection.topLeft => const Offset(-500, -350),
        _FlyDirection.topRight => const Offset(500, -350),
        _FlyDirection.bottomLeft => const Offset(-500, 350),
        _FlyDirection.bottomRight => const Offset(500, 350),
      };

  /// 初始旋转角（度）。
  double get rotation => switch (this) {
        _FlyDirection.topLeft => -30,
        _FlyDirection.topRight => 30,
        _FlyDirection.bottomLeft => 25,
        _FlyDirection.bottomRight => -25,
      };
}

/// 单个字母配置（对齐 iOS `LetterImageConfig` 的时序字段）。
class _LetterSpec {
  const _LetterSpec(this.letter, this.size, this.direction, this.delay);

  /// 字面。
  final String letter;

  /// 字号。
  final double size;

  /// 飞入方向。
  final _FlyDirection direction;

  /// 延时（秒）。
  final double delay;
}

/// 品牌启动页。
class VboxSplashView extends StatefulWidget {
  /// 构造。
  const VboxSplashView({super.key});

  /// 飞入聚合总时长。
  static const Duration enterDuration = Duration(milliseconds: 900);

  @override
  State<VboxSplashView> createState() => _VboxSplashViewState();
}

class _VboxSplashViewState extends State<VboxSplashView>
    with TickerProviderStateMixin {
  /// 字母配置（V 大一号，box 缩小，对齐 iOS v9 层级）。
  static const List<_LetterSpec> _letters = <_LetterSpec>[
    _LetterSpec('V', 100, _FlyDirection.topLeft, 0.00),
    _LetterSpec('b', 85, _FlyDirection.bottomLeft, 0.08),
    _LetterSpec('o', 85, _FlyDirection.topRight, 0.14),
    _LetterSpec('x', 85, _FlyDirection.bottomRight, 0.20),
  ];

  /// 进入（飞入聚合 + swoosh 扫入）。
  late final AnimationController _enter;

  /// 发光（聚合后常亮）。
  late final AnimationController _glow;

  /// 呼吸缩放（无限循环）。
  late final AnimationController _breath;

  /// 上下浮动（无限循环）。
  late final AnimationController _float;

  final List<Timer> _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: VboxSplashView.enterDuration)
      ..forward();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    // 第 2 阶段：聚合完成后发光（0.7s）。
    _timers.add(Timer(const Duration(milliseconds: 700), () {
      if (mounted) _glow.forward();
    }));
    // 第 3 阶段：进入呼吸 + 浮动无限循环（1.0s）。
    _timers.add(Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      _breath.repeat(reverse: true);
      _float.repeat(reverse: true);
    }));
  }

  @override
  void dispose() {
    for (final Timer t in _timers) {
      t.cancel();
    }
    _enter.dispose();
    _glow.dispose();
    _breath.dispose();
    _float.dispose();
    super.dispose();
  }

  /// 单个字母的入场进度曲线（按错峰延时切 Interval）。
  Animation<double> _letterProgress(double delay) {
    final double begin = (delay / 0.9).clamp(0.0, 0.99);
    return CurvedAnimation(
      parent: _enter,
      curve: Interval(begin, 1, curve: Curves.easeOutBack),
    );
  }

  /// 单个字母的透明度曲线（更早到达 1）。
  Animation<double> _letterOpacity(double delay) {
    final double begin = (delay / 0.9).clamp(0.0, 0.9);
    final double end = (begin + 0.4).clamp(0.1, 1.0);
    return CurvedAnimation(parent: _enter, curve: Interval(begin, end));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final List<Color> background = vboxSplashGradient(Theme.of(context).brightness);
    final Color subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.18);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: background,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Center(child: _logo()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: _subtitle(subtitleColor),
          ),
        ],
      ),
    );
  }

  /// 字标：swoosh 托底 + 四字母飞入聚合 + 发光 + 呼吸浮动。
  Widget _logo() {
    return AnimatedBuilder(
      animation: _breath,
      builder: (BuildContext context, Widget? child) {
        final double scale = 1 + 0.05 * _breath.value;
        return AnimatedBuilder(
          animation: _float,
          builder: (BuildContext context, Widget? _) {
            final double dy = -6 + 12 * _float.value;
            return Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: child,
        );
      },
      child: SizedBox(
        width: 182.2,
        height: 100,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            _swoosh(),
            // 字标总宽受 iOS 聚合宽度 182.2 约束；品牌字体自然宽度（≈217.6pt）
            // 超出该宽度，等比缩至贴合（`scaleDown`），避免溢出且保持「V 大 box 小」层级。
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: _letters
                    .map((_LetterSpec spec) => _letter(spec))
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// swoosh 托底（从左向右扫入，顺时针 4°）。
  Widget _swoosh() {
    final Animation<double> progress = CurvedAnimation(
      parent: _enter,
      curve: const Interval(0.33, 1, curve: Curves.easeOut),
    );
    final Animation<double> opacity = CurvedAnimation(
      parent: _enter,
      curve: const Interval(0.33, 0.7),
    );
    return Positioned(
      left: 0,
      top: 72.3,
      child: AnimatedBuilder(
        animation: progress,
        builder: (BuildContext context, Widget? child) {
          return Opacity(
            opacity: opacity.value,
            child: Transform.translate(
              offset: Offset(-160 * (1 - progress.value), 0),
              child: Transform.rotate(angle: 4 * 3.1415926535 / 180, child: child),
            ),
          );
        },
        child: Container(
          width: 182.2,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0x003B82F6),
                VboxColors.brandGradientStart,
                VboxColors.brandGradientEnd,
              ],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: VboxColors.brandGradientStart.withValues(alpha: 0.45),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单字母：位移 + 旋转 + 透明度入场，聚合后常亮发光。
  Widget _letter(_LetterSpec spec) {
    final Animation<double> progress = _letterProgress(spec.delay);
    final Animation<double> opacity = _letterOpacity(spec.delay);
    final TextStyle style = TextStyle(
      fontFamily: VboxBrand.fontFamily,
      fontSize: spec.size,
      height: 1,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFF1B1B1F),
    );
    return AnimatedBuilder(
      animation: progress,
      builder: (BuildContext context, Widget? child) {
        final double p = progress.value;
        final Offset offset = spec.direction.offset * (1 - p);
        final double rotation = spec.direction.rotation * (1 - p) * 3.1415926535 / 180;
        return Opacity(
          opacity: opacity.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: offset,
            child: Transform.rotate(angle: rotation, child: child),
          ),
        );
      },
      child: Stack(
        children: <Widget>[
          // 发光层（聚合完成后常亮）。
          FadeTransition(
            opacity: _glow,
            child: Text(
              spec.letter,
              style: style.copyWith(
                shadows: <Shadow>[
                  Shadow(
                    color: VboxColors.brandGradientStart.withValues(alpha: 0.5),
                    blurRadius: 14,
                  ),
                ],
                color: Colors.transparent,
              ),
            ),
          ),
          Text(spec.letter, style: style),
        ],
      ),
    );
  }

  /// 底部小字 + 版本号。
  Widget _subtitle(Color color) {
    return FadeTransition(
      opacity: _glow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '愿你每一次观影都能释放现有压力',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 2,
              color: color,
            ),
          ),
          Text(
            'vbox聚合观影软件由Ai开发而来',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 2,
              color: color,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppInfo.version,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              color: color.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}