/// 表现层：福利平台路由（批次 H · H-02）。
///
/// 唯一真相源：iOS `vbox/WelfareRemote/WelfarePlatformRouter.swift`
///   · `makeDestinationView(for:settings:)`（L96-L154）：按 `serviceType` 分发；
///   · `makeFuliBaseDestination`（L160-L184）：`fuli_base` 按 `platformKey` 映射子类；
///   · `makeWelfareSpiderDestination`（L196-L226）：JS 脚本 → JS 引擎页，
///     其余 → Spider 脚本状态页；
///   · `unknown` → `UnsupportedPlatformView`（**不兜底**到其他平台）。
///
/// 移植口径：本批产出**路由描述**（[WelfareRoute]），不直接产出 Widget ——
/// 目标页面（`FuliPlatformMainView` 等）随「福利原生平台 / H-03 Spider」批次落地；
/// 页面层据描述构建实际页面（当前 `unknown` / 未注册 → [WelfareUnsupportedRoute]）。
library;

import '../../domain/entities/welfare/welfare.dart';
import '../../domain/services/fuli_base_service.dart';

/// 原生专用平台种类（对齐 iOS 三个专用 View）。
enum WelfareNativeKind {
  /// 香蕉秀专用（`ybox_special` → `YBoxXjspMainView`）。
  bananaXjsp('香蕉秀专用页'),

  /// 每日大乱斗 / 每日大赛（`daily_battle` → `DailyBattleMainView`）。
  dailyBattle('每日大乱斗页'),

  /// 今日看料（`kanliao` → `KanliaoHomeView`）。
  kanliao('今日看料页');

  const WelfareNativeKind(this.label);

  /// 目标页面中文名。
  final String label;
}

/// 福利平台路由结果（按 [WelfarePlatform.service] 解析）。
sealed class WelfareRoute {
  /// 构造。
  const WelfareRoute(this.platform);

  /// 触发路由的平台元数据。
  final WelfarePlatform platform;

  /// 目标页面族中文名（提示 / 测试断言用）。
  String get destinationLabel;
}

/// 原生专用平台页（`ybox_special` / `daily_battle` / `kanliao`）。
final class WelfareNativeRoute extends WelfareRoute {
  /// 构造。
  const WelfareNativeRoute(super.platform, this.kind);

  /// 原生专用种类。
  final WelfareNativeKind kind;

  @override
  String get destinationLabel => kind.label;
}

/// 艾旦福利视频页（`aidan_video`，CMS V10 专用）。
final class WelfareAidanVideoRoute extends WelfareRoute {
  /// 构造。
  const WelfareAidanVideoRoute(super.platform);

  @override
  String get destinationLabel => '艾旦福利视频页';
}

/// 通用福利平台页（`fuli_base`，服务已注册）。
final class WelfareFuliBaseRoute extends WelfareRoute {
  /// 构造。
  const WelfareFuliBaseRoute(super.platform, this.service);

  /// 命中的服务实例。
  final FuliBaseService service;

  @override
  String get destinationLabel => '通用福利平台页';
}

/// 远程 CMS V10 福利页（`remote_cms_v10`）。
final class WelfareRemoteCmsV10Route extends WelfareRoute {
  /// 构造。
  const WelfareRemoteCmsV10Route(super.platform);

  @override
  String get destinationLabel => '远程 CMS V10 福利页';
}

/// 福利 JS Spider 页（`welfare_spider` + `scriptType == javascript`）。
final class WelfareWelfareSpiderRoute extends WelfareRoute {
  /// 构造。
  const WelfareWelfareSpiderRoute(super.platform);

  @override
  String get destinationLabel => '福利 JS Spider 页';
}

/// 福利 Spider 脚本状态页（`welfare_spider` 非 JS）。
final class WelfareSpiderHomeRoute extends WelfareRoute {
  /// 构造。
  const WelfareSpiderHomeRoute(super.platform);

  @override
  String get destinationLabel => '福利 Spider 脚本页';
}

/// 福利 Python Spider 页（`python_spider`）。
final class WelfarePythonSpiderRoute extends WelfareRoute {
  /// 构造。
  const WelfarePythonSpiderRoute(super.platform);

  @override
  String get destinationLabel => '福利 Python Spider 页';
}

/// 未支持平台页（`unknown` / `fuli_base` 未注册服务）。
final class WelfareUnsupportedRoute extends WelfareRoute {
  /// 构造。
  const WelfareUnsupportedRoute(super.platform, this.reason);

  /// 未支持原因（排查日志 / 页面展示用）。
  final String reason;

  @override
  String get destinationLabel => '未支持平台页';
}

/// 福利平台路由分发器（对齐 iOS `WelfarePlatformRouter`）。
class WelfarePlatformRouter {
  /// 构造（注册表可注入，默认取全局共享实例）。
  WelfarePlatformRouter({FuliBaseServiceRegistry? registry})
      : _registry = registry ?? FuliBaseServiceRegistry.shared;

  final FuliBaseServiceRegistry _registry;

  /// 按 `serviceType` 解析路由（5 类路由 + 原生专用 + 未支持）。
  WelfareRoute resolve(WelfarePlatform platform) {
    switch (platform.service) {
      case WelfareServiceType.yboxSpecial:
        return WelfareNativeRoute(platform, WelfareNativeKind.bananaXjsp);
      case WelfareServiceType.dailyBattle:
        return WelfareNativeRoute(platform, WelfareNativeKind.dailyBattle);
      case WelfareServiceType.kanliao:
        return WelfareNativeRoute(platform, WelfareNativeKind.kanliao);
      case WelfareServiceType.aidanVideo:
        return WelfareAidanVideoRoute(platform);
      case WelfareServiceType.fuliBase:
        final FuliBaseService? service =
            _registry.serviceFor(platform.platformKey);
        if (service == null) {
          return WelfareUnsupportedRoute(
            platform,
            'fuli_base 平台未注册服务：${platform.platformKey}',
          );
        }
        return WelfareFuliBaseRoute(platform, service);
      case WelfareServiceType.remoteCmsV10:
        return WelfareRemoteCmsV10Route(platform);
      case WelfareServiceType.welfareSpider:
        // 对齐 iOS：JS 脚本 → JS 引擎页；其余 → 脚本状态页。
        return platform.isJavaScriptSpider
            ? WelfareWelfareSpiderRoute(platform)
            : WelfareSpiderHomeRoute(platform);
      case WelfareServiceType.pythonSpider:
        return WelfarePythonSpiderRoute(platform);
      case WelfareServiceType.unknown:
        return WelfareUnsupportedRoute(
          platform,
          platform.serviceType.trim().isEmpty
              ? '远程配置缺少 serviceType'
              : '未知 serviceType：${platform.serviceType}',
        );
    }
  }
}