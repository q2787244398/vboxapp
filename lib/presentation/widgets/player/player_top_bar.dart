/// 表现层：播放器顶栏（批次 C · C-02）。
///
/// 对齐 iOS `PlayerTopBarView`（[PlayerViewsV2.swift](../../../../vbox/Views/PlayerViewsV2.swift#L7665)）：
/// 左上「返回 + 标题 + 副标题（第 N 集 · 源）」；右上「投屏 + 更多 + 可选锁定」。
/// 横竖共用同一结构，仅内边距 / 字号差异（表单态由 [form] 驱动）。
library;

import 'package:flutter/material.dart';

import '../../theme/tokens/colors.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../ui_mode/ui_mode.dart';

/// 播放器顶栏。
class PlayerTopBar extends StatelessWidget {
  /// 构造。
  const PlayerTopBar({
    super.key,
    required this.form,
    this.title,
    this.subtitle,
    this.showLock = false,
    this.locked = false,
    this.onBack,
    this.onCast,
    this.onToggleLock,
    this.onToolsMenu,
  });

  /// 显示形态。
  final UiForm form;

  /// 主标题（剧名）。
  final String? title;

  /// 副标题（集数 · 源）。
  final String? subtitle;

  /// 是否显示锁定按钮（仅横屏 / 竖屏全屏）。
  final bool showLock;

  /// 是否已锁定方向。
  final bool locked;

  /// 返回回调。
  final VoidCallback? onBack;

  /// 投屏回调。
  final VoidCallback? onCast;

  /// 锁定切换回调。
  final VoidCallback? onToggleLock;

  /// 更多菜单回调。
  final VoidCallback? onToolsMenu;

  @override
  Widget build(BuildContext context) {
    final bool landscape = form.isLandscape;
    const Color foreground = Colors.white;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: landscape ? VboxSpacing.lg : VboxSpacing.md,
          vertical: VboxSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            _IconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              color: foreground,
              onTap: onBack,
            ),
            const SizedBox(width: VboxSpacing.xs),
            // 标题区（可收缩）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (title != null)
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: VboxTypography.s16,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: VboxTypography.s12,
                        color: Colors.white70,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white38,
                      ),
                    ),
                ],
              ),
            ),
            if (showLock) ...<Widget>[
              _IconButton(
                icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: locked ? VboxColors.chipSelected : foreground,
                onTap: onToggleLock,
              ),
            ],
            _IconButton(
              icon: Icons.cast_rounded,
              color: foreground,
              onTap: onCast,
            ),
            _IconButton(
              icon: Icons.more_vert_rounded,
              color: foreground,
              onTap: onToolsMenu,
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏图标按钮（统一热区 44×44，避免散落魔数）。
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22, color: color),
      constraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: VboxRadii.button),
      ),
    );
  }
}
