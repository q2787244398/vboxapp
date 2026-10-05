/// 网盘授权中心共享组件（批次 F · F-01，对齐 iOS UI 图 14）。
///
/// 组件与 iOS `SettingsViews` 授权中心私有视图一一对应：
/// `nodeRuntimeStatusBanner` / `accountHeader` / `authStatusRow` /
/// `authButtonLabel` / `authDetailLine`。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import 'cloud_drive_auth_controller.dart';

/// 网盘列表图标（对齐 iOS `CloudDriveSortView.icon(for:)`，配色统一走
/// [VboxColors.selected] 蓝，与 iOS 排序列表蓝色图标一致）。
IconData cloudDriveIcon(CloudDriveType type) => switch (type) {
      CloudDriveType.ali => Icons.cloud_outlined,
      CloudDriveType.quark => Icons.link,
      CloudDriveType.quarkNode => Icons.square_outlined,
      CloudDriveType.baidu => Icons.link,
      CloudDriveType.baiduNode => Icons.square_outlined,
      CloudDriveType.one15 => Icons.cloud_outlined,
      CloudDriveType.uc => Icons.send,
      CloudDriveType.ucNode => Icons.square_outlined,
      CloudDriveType.pan123 => Icons.storage,
      CloudDriveType.pan139 => Icons.all_inbox,
      CloudDriveType.pan189 => Icons.cloud,
      CloudDriveType.xunlei => Icons.bolt,
      CloudDriveType.guangya => Icons.circle_outlined,
      CloudDriveType.woniu4k => Icons.circle_outlined,
      CloudDriveType.bilibili => Icons.tv,
    };

/// 各网盘授权动作按钮（标签 + 图标，逐档对齐 iOS `providerAccountCard` /
/// `nodeManagedAccountCard` 的分支文案；阿里与三张 Node 托管卡为单按钮）。
List<(String, IconData)> cloudDriveAuthActions(CloudDriveType type) =>
    switch (type) {
      CloudDriveType.ali => <(String, IconData)>[
          ('PG扫码登录', Icons.qr_code_2),
        ],
      CloudDriveType.uc || CloudDriveType.ucNode => <(String, IconData)>[
          ('原生扫码', Icons.qr_code_2),
          ('网页登录兜底', Icons.language),
        ],
      CloudDriveType.baidu || CloudDriveType.baiduNode => <(String, IconData)>[
          ('扫码授权', Icons.qr_code_2),
          ('网页兜底', Icons.language),
        ],
      CloudDriveType.quark || CloudDriveType.quarkNode => <(String, IconData)>[
          ('扫码登录', Icons.qr_code_2),
          ('网页登录兜底', Icons.language),
        ],
      CloudDriveType.one15 => <(String, IconData)>[
          ('Node扫码登录', Icons.phone_iphone),
          ('网页兜底', Icons.language),
        ],
      CloudDriveType.pan123 => <(String, IconData)>[
          ('Node账号登录', Icons.phone_iphone),
          ('网页兜底', Icons.language),
        ],
      CloudDriveType.pan139 ||
      CloudDriveType.pan189 ||
      CloudDriveType.xunlei =>
        <(String, IconData)>[
          ('Node验证码登录', Icons.phone_iphone),
          ('网页兜底', Icons.language),
        ],
      CloudDriveType.guangya => <(String, IconData)>[
          ('手机验证码登录', Icons.phone_iphone),
        ],
      CloudDriveType.woniu4k => <(String, IconData)>[
          ('账号登录', Icons.person_outline),
        ],
      CloudDriveType.bilibili => <(String, IconData)>[
          ('原生扫码', Icons.qr_code_2),
        ],
    };

/// 网盘品牌角标底色（未登记回退分类色板的云盘蓝）。
Color cloudDriveBrandColor(CloudDriveType type) =>
    VboxColors.cloudDriveBrandColors[type.id] ??
    VboxColors.categoryColors[VboxCategory.cloud]!;

/// 品牌角标字母（对齐 iOS 图标语义的极简字形）。
const Map<CloudDriveType, String> _brandLetters = <CloudDriveType, String>{
  CloudDriveType.ali: 'A',
  CloudDriveType.quark: 'Q',
  CloudDriveType.quarkNode: 'Q',
  CloudDriveType.baidu: 'B',
  CloudDriveType.baiduNode: 'B',
  CloudDriveType.one15: '1',
  CloudDriveType.uc: 'U',
  CloudDriveType.ucNode: 'U',
  CloudDriveType.pan123: '1',
  CloudDriveType.pan139: '1',
  CloudDriveType.pan189: 'T',
  CloudDriveType.xunlei: 'X',
  CloudDriveType.guangya: 'G',
  CloudDriveType.woniu4k: 'W',
  CloudDriveType.bilibili: 'B',
};

/// 网盘品牌圆形角标（授权中心 / 排序列表共用）。
class VboxDriveLogo extends StatelessWidget {
  /// 构造。
  const VboxDriveLogo({super.key, required this.type, this.size = 28});

  /// 网盘类型。
  final CloudDriveType type;

  /// 边长。
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cloudDriveBrandColor(type),
        shape: BoxShape.circle,
      ),
      child: Text(
        _brandLetters[type] ?? '?',
        style: TextStyle(
          fontSize: size >= 32 ? VboxTypography.s16 : VboxTypography.s13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Node 常驻系统状态横幅（对齐 iOS `nodeRuntimeStatusBanner`）。
class VboxNodeStatusBanner extends StatelessWidget {
  /// 构造。
  const VboxNodeStatusBanner({super.key, required this.status});

  /// 状态快照。
  final NodeRuntimeStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = _nodeStatusColor(scheme, status.state);
    return Container(
      padding: const EdgeInsets.all(VboxSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: VboxRadii.card,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 26,
            child: Icon(
              _nodeStatusIcon(status.state),
              size: VboxTypography.s16,
              color: color,
            ),
          ),
          const SizedBox(width: VboxSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'Node 常驻系统',
                      style: TextStyle(
                        fontSize: VboxTypography.s14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: VboxSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(VboxRadii.r6),
                      ),
                      child: Text(
                        status.state.displayText,
                        style: TextStyle(
                          fontSize: VboxTypography.s11,
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  status.detailText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: VboxTypography.s11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 网盘账户卡（对齐 iOS `accountHeader` + `authStatusRow` + `authDetailLine`）。
class VboxDriveAccountCard extends StatelessWidget {
  /// 构造。
  const VboxDriveAccountCard({
    super.key,
    required this.account,
    this.onTest,
    this.onAction,
  });

  /// 账户视图模型。
  final CloudDriveAccount account;

  /// 「测试」回调。
  final VoidCallback? onTest;

  /// 登录动作回调（动作名见 [actions]）。
  final void Function(String action)? onAction;

  /// 登录动作（逐档对齐 iOS，见 [cloudDriveAuthActions]）。
  List<(String, IconData)> get actions => cloudDriveAuthActions(account.type);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color statusColor =
        account.statusReady ? VboxColors.success : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(VboxSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: VboxRadii.chip,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: <Widget>[
          _header(scheme),
          if (account.hasCookieRow)
            _cookieRow(scheme, statusColor),
          if (account.description != null)
            Text(
              account.description!,
              style: TextStyle(
                fontSize: VboxTypography.s12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          Row(
            spacing: 10,
            children: <Widget>[
              for (final (String, IconData) action in actions)
                Expanded(
                  child: _actionButton(
                    context,
                    scheme,
                    label: action.$1,
                    icon: action.$2,
                  ),
                ),
            ],
          ),
          _detailLine(scheme, statusColor),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Row(
      spacing: VboxSpacing.md,
      children: <Widget>[
        VboxDriveLogo(type: account.type, size: 36),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                account.type.displayName,
                style: TextStyle(
                  fontSize: VboxTypography.s16,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                account.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: VboxTypography.s12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _badge(
          text: account.authorized ? '已获取' : '未获取',
          color: account.authorized ? VboxColors.success : scheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _cookieRow(ColorScheme scheme, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(VboxRadii.r10),
      ),
      child: Row(
        children: <Widget>[
          Text(
            account.cookieLabel!,
            style: TextStyle(
              fontSize: VboxTypography.s13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          Icon(
            account.cookieReady ? Icons.check_circle : Icons.error_outline,
            size: VboxTypography.s13,
            color: account.cookieReady ? VboxColors.success : VboxColors.warning,
          ),
          const SizedBox(width: VboxSpacing.xs),
          Text(
            account.cookieStatusText,
            style: TextStyle(
              fontSize: VboxTypography.s12,
              color: account.cookieReady ? VboxColors.success : VboxColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    ColorScheme scheme, {
    required String label,
    required IconData icon,
  }) {
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(VboxRadii.r10),
      child: InkWell(
        onTap: onAction == null ? null : () => onAction!(label),
        borderRadius: BorderRadius.circular(VboxRadii.r10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: VboxTypography.s14, color: scheme.onPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: VboxTypography.s13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailLine(ColorScheme scheme, Color statusColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(VboxRadii.r10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              account.detailFallback,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: VboxTypography.s12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            account.statusText,
            style: TextStyle(
              fontSize: VboxTypography.s12,
              fontWeight: FontWeight.w500,
              color: statusColor,
            ),
          ),
          const SizedBox(width: VboxSpacing.sm),
          TextButton(
            key: ValueKey<String>(CloudDriveAccount.actionKey(account.type)),
            onPressed: onTest,
            style: TextButton.styleFrom(
              backgroundColor: scheme.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(VboxRadii.r8),
              ),
            ),
            child: Text(
              '测试',
              style: TextStyle(
                fontSize: VboxTypography.s11,
                fontWeight: FontWeight.w500,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VboxRadii.r8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: VboxTypography.s12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

Color _nodeStatusColor(ColorScheme scheme, NodeRuntimeState state) {
  if (state.isReady) return VboxColors.success;
  if (state == NodeRuntimeState.memoryWarning ||
      state == NodeRuntimeState.starting) {
    return VboxColors.warning;
  }
  if (state.isError) return scheme.error;
  return scheme.onSurfaceVariant;
}

IconData _nodeStatusIcon(NodeRuntimeState state) {
  if (state.isReady) return Icons.check_circle;
  if (state == NodeRuntimeState.memoryWarning) {
    return Icons.warning_amber_rounded;
  }
  if (state.isError) return Icons.error;
  if (state == NodeRuntimeState.starting) return Icons.hourglass_bottom;
  if (state == NodeRuntimeState.stopped) return Icons.power_settings_new;
  return Icons.help_outline;
}
