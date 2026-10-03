/// 福利专区首页（批次 H · H-06）。
///
/// 唯一真相源：iOS `vbox/WelfareRemote/RemoteWelfareHomeView.swift`
///   · `tabBar`（L119-L154）：三段等宽分段，选中 = 实心渐变 + 白字；
///   · `platformGrid(for:)`（L174-L243）：`LazyVGrid` 4 列 + `RemotePlatformIconCard`，
///     空态 = `square.grid.3x3`（40）+「此分类下暂无平台」（15, secondary）；
///   · 网格内边距 `.horizontal 16 / .top 8 / .bottom 100`。
///
/// 数据来自 [WelfarePlatformController]（H-01）：进入页面 `bootstrap()`（幂等）
/// 恢复缓存并后台刷新；分段切换只切**当前分类的网格**，不重新联网。
///
/// 与 iOS 的差异（如实登记）：
///   · iOS 平台图标为 SF Symbol（`platform.icon`），Flutter 无法渲染 → 按
///     [welfarePlatformIcon] 映射 Material 近似图标，未知符号回退 `apps`；
///   · 长按进入**编辑排序**（拖拽 + 边缘自动滚动 + 震动）未在本批实现，
///     随 H-07 排序持久化一并接入；本页点击平台经 [WelfarePlatformRouter]
///     路由（H-02）：未支持 → [UnsupportedPlatformPage]；福利 Spider
///     JS / Python → [WelfareSpiderMainPage]（H-03 续段：JS 引擎 / Python 桥
///     执行页）；其余 Spider 脚本 → [WelfareSpiderHomePage]（脚本状态页）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/welfare/welfare.dart';
import '../../../domain/services/welfare_js_spider_service.dart';
import '../../../domain/services/welfare_python_spider_service.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../welfare/welfare_platform_controller.dart';
import '../../welfare/welfare_platform_router.dart';
import '../../widgets/vbox/vbox.dart';
import 'unsupported_platform_page.dart';
import 'welfare_spider_home_page.dart';
import 'welfare_spider_main_page.dart';

/// 福利专区首页（远程源版，三栏目 + 平台网格）。
class WelfareHomePage extends StatefulWidget {
  /// 构造。
  const WelfareHomePage({super.key});

  @override
  State<WelfareHomePage> createState() => _WelfareHomePageState();
}

class _WelfareHomePageState extends State<WelfareHomePage> {
  /// 当前栏目（默认「视频」，对齐 iOS `selectedTab = .video`）。
  VboxWelfareCategory _tab = VboxWelfareCategory.video;

  /// 平台路由分发器（H-02）。
  final WelfarePlatformRouter _router = WelfarePlatformRouter();

  @override
  void initState() {
    super.initState();
    // 幂等：仅在首次进入时恢复缓存 + 后台刷新。
    context.read<WelfarePlatformController>().bootstrap();
  }

  /// 当前栏目对应的领域分类（枚举名与契约 key 一致：video / live / comic）。
  WelfarePlatformCategory get _category =>
      WelfarePlatformCategory.fromKey(_tab.name) ?? WelfarePlatformCategory.video;

  @override
  Widget build(BuildContext context) {
    final WelfarePlatformController controller =
        context.watch<WelfarePlatformController>();
    final List<WelfarePlatform> platforms = controller.platformsIn(_category);

    return Scaffold(
      appBar: AppBar(
        title: const Text('福利专区'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _onRefresh(controller),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          VboxWelfareTabs(
            selected: _tab,
            onSelected: (VboxWelfareCategory tab) => setState(() => _tab = tab),
          ),
          Expanded(child: _content(controller, platforms)),
        ],
      ),
    );
  }

  void _onRefresh(WelfarePlatformController controller) {
    if (!controller.switchEnabled) {
      VboxToast.show(context, '请先在「我的 → 福利专区」启用远程源');
      return;
    }
    controller.refresh();
  }

  Widget _content(
    WelfarePlatformController controller,
    List<WelfarePlatform> platforms,
  ) {
    if (platforms.isNotEmpty) {
      final Map<String, WelfarePlatform> byKey = <String, WelfarePlatform>{
        for (final WelfarePlatform p in platforms) p.platformKey: p,
      };
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          VboxSpacing.lg,
          VboxSpacing.sm,
          VboxSpacing.lg,
          100,
        ),
        child: VboxWelfarePlatformGrid(
          platforms: platforms
              .map((WelfarePlatform p) => VboxWelfarePlatform(
                    name: p.name,
                    icon: welfarePlatformIcon(p.icon),
                    platformKey: p.platformKey,
                  ))
              .toList(growable: false),
          onTap: (VboxWelfarePlatform p) {
            final WelfarePlatform? target = byKey[p.platformKey];
            if (target != null) _onPlatformTap(target);
          },
        ),
      );
    }

    if (controller.loadState == WelfarePlatformLoadState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool failed =
        controller.loadState == WelfarePlatformLoadState.failed;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VboxSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              failed ? Icons.cloud_off_rounded : Icons.grid_view_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: VboxSpacing.md),
            Text(
              failed ? (controller.errorMessage ?? '福利内容加载失败') : '此分类下暂无平台',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: VboxTypography.s15,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            if (failed) ...<Widget>[
              const SizedBox(height: VboxSpacing.md),
              VboxButton(
                label: '重试',
                onPressed: () => context.read<WelfarePlatformController>().refresh(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 按 [WelfarePlatformRouter] 解析并跳转（H-02）。
  ///
  /// 未支持（`unknown` / `fuli_base` 未注册 / 隔离违规）→ [UnsupportedPlatformPage]；
  /// 福利 JS Spider（H-03 续段）→ [WelfareSpiderMainPage]（JS 引擎执行页，
  /// 对齐 iOS `FuliPlatformMainView + WelfareJSSpiderService`）；
  /// 福利 Python Spider → [WelfareSpiderMainPage]（Python 桥执行页，
  /// 对齐 iOS `WelfarePythonSpiderService`）；
  /// 其余福利 Spider 脚本 → [WelfareSpiderHomePage]（脚本状态页）。
  void _onPlatformTap(WelfarePlatform platform) {
    final WelfareRoute route = _router.resolve(platform);
    if (route is WelfareUnsupportedRoute) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => UnsupportedPlatformPage(
            platform: platform,
            reason: route.reason,
          ),
        ),
      );
      return;
    }
    if (route is WelfareWelfareSpiderRoute) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => WelfareSpiderMainPage(
            platform: platform,
            service: WelfareJSSpiderService.serviceFor(platform),
          ),
        ),
      );
      return;
    }
    if (route is WelfarePythonSpiderRoute) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => WelfareSpiderMainPage(
            platform: platform,
            service: WelfarePythonSpiderService.serviceFor(platform),
          ),
        ),
      );
      return;
    }
    if (route is WelfareSpiderHomeRoute) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              WelfareSpiderHomePage(platform: platform),
        ),
      );
      return;
    }
    VboxToast.show(context, '「${platform.name}」路由至 ${route.destinationLabel}');
  }
}

/// SF Symbol 名 → Material 近似图标（未知符号回退 `apps`）。
///
/// iOS 平台图标为远程配置的 SF Symbol 字符串，Flutter 侧无法解析；
/// 仅覆盖远程配置中的常见符号，其余统一兜底，避免整格空白。
IconData welfarePlatformIcon(String? symbol) {
  switch (symbol) {
    case 'play.rectangle.fill':
      return Icons.smart_display_rounded;
    case 'antenna.radiowaves.left.and.right':
      return Icons.podcasts;
    case 'books.vertical.fill':
      return Icons.menu_book_rounded;
    case 'leaf.fill':
      return Icons.eco_rounded;
    case 'film.fill':
      return Icons.movie_rounded;
    case 'tv.fill':
      return Icons.tv_rounded;
    case 'music.note':
      return Icons.music_note_rounded;
    case 'video.fill':
      return Icons.videocam_rounded;
    case 'photo.fill':
      return Icons.photo_rounded;
    case 'flame.fill':
      return Icons.local_fire_department_rounded;
    case 'star.fill':
      return Icons.star_rounded;
    default:
      return Icons.apps_rounded;
  }
}