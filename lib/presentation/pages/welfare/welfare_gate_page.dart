/// 福利 Tab 落地页（批次 A · A8 门控骨架；完整三栏目见 H-06）。
///
/// 唯一真相源：iOS `WelfareTabGateView`（底栏「福利」选中后进入）。
///
/// 本文件只提供**门控落地骨架**：顶栏「刷新」+ 空态，确保 A8 门控链路
/// （解锁 → 底栏插入「福利」→ 点击可进入）端到端可用；三栏目分段控件
/// 与平台图标网格由批次 H-06 在 `welfare_platform_grid` 等组件落地后替换。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/vbox_skin_controller.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../welfare/welfare_controller.dart';
import '../../widgets/vbox/vbox.dart';

/// 福利 Tab 落地页。
class WelfareGatePage extends StatelessWidget {
  /// 构造。
  const WelfareGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final Color accent = context.watch<VboxSkinController>().skin.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('福利专区'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final WelfareController controller =
                  context.read<WelfareController>();
              VboxToast.show(
                context,
                controller.enabled ? '已是最新' : '请先在「我的」启用福利专区',
              );
            },
          ),
        ],
      ),
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
                '点击右上角刷新，或前往「我的 → 福利专区」管理平台',
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