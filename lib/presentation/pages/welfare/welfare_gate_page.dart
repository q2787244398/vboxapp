/// 福利 Tab 落地页 / 路由门（批次 A · A8 门控骨架 → 批次 H · H-06 TabGate）。
///
/// 唯一真相源：iOS `vbox/WelfareRemote/WelfareTabGateView.swift`
///   · `WelfarePlatformConfigStore.shared.switchEnabled` 为真 → `RemoteWelfareHomeView`
///     （远程源版三栏目，见 [WelfareHomePage]）；
///   · 为假 → `WelfareHomeView`（**内置资源版**）。
///
/// 门控前置：契约键 `fuli_remote_source_enabled` 由 [WelfarePlatformController]
/// 异步读入，故本页先 `await bootstrap()` 再判定，避免「已关闭仍闪远程页」。
///
/// 遗留（如实登记）：内置资源版 `WelfareHomeView` 尚未移植（依赖 H-02 路由 /
/// H-03 Spider），当前以显式占位呈现；关闭远程源开关后的完整内置链路随 H-02/H-03 接入。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/vbox_skin_controller.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../welfare/welfare_platform_controller.dart';
import 'welfare_home_page.dart';

/// 福利 Tab 路由门（远程源 ⇄ 内置资源）。
class WelfareGatePage extends StatefulWidget {
  /// 构造。
  const WelfareGatePage({super.key});

  @override
  State<WelfareGatePage> createState() => _WelfareGatePageState();
}

class _WelfareGatePageState extends State<WelfareGatePage> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // 先读开关（bootstrap 内部：读开关 → 恢复缓存 → 开关开启才后台刷新）。
    context.read<WelfarePlatformController>().bootstrap().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final WelfarePlatformController controller =
        context.watch<WelfarePlatformController>();
    return controller.switchEnabled
        ? const WelfareHomePage()
        : const _BuiltinWelfarePage();
  }
}

/// 内置福利资源版占位（对齐 iOS `WelfareHomeView`，待 H-02 / H-03 接入）。
class _BuiltinWelfarePage extends StatelessWidget {
  const _BuiltinWelfarePage();

  @override
  Widget build(BuildContext context) {
    final Color accent = context.watch<VboxSkinController>().skin.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('福利专区')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(VboxSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.card_giftcard, size: 48, color: accent),
              const SizedBox(height: VboxSpacing.lg),
              const Text(
                '暂无福利内容',
                style: TextStyle(
                  fontSize: VboxTypography.s16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: VboxSpacing.sm),
              Text(
                '内置福利资源随 H-02 / H-03 接入；也可在「我的 → 福利专区」启用远程源',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: VboxTypography.s13,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}