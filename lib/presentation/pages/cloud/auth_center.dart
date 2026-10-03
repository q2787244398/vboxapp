/// 网盘账号授权中心页（批次 F · F-01，对齐 iOS UI 图 14）。
///
/// 对齐 iOS `CloudAuthCenterView`（`vbox/Views/SettingsViews.swift:1561`）：
/// 顶栏「网盘账号授权 + 完成」· Node 常驻系统状态横幅 · 12 张网盘账号卡
/// （9 普通 + 3 Node 托管）· 底部说明文案。
///
/// 数据由 [CloudDriveAuthController] 提供（读契约安全存储
/// `cloud_drive_credentials_v1`）。授权动作（扫码 / 短信 / 网页兜底）随
/// F-02 授权链落地，本页先以回调外抛（缺省轻提示占位）。
library;

import 'package:flutter/material.dart';

import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/vbox/vbox.dart';
import 'cloud_drive_auth_controller.dart';
import 'cloud_drive_widgets.dart';
import 'sort.dart';

/// 网盘账号授权中心页。
class CloudDriveAuthCenterPage extends StatefulWidget {
  /// 构造（[controller] 供测试注入；缺省自建并自管生命周期）。
  const CloudDriveAuthCenterPage({super.key, this.controller, this.onAction});

  /// 外部注入的控制器（null → 页面自建）。
  final CloudDriveAuthController? controller;

  /// 授权动作回调（null → 轻提示占位；F-02 接入登录链后由外部接管）。
  final void Function(CloudDriveAccount account, String action)? onAction;

  @override
  State<CloudDriveAuthCenterPage> createState() =>
      _CloudDriveAuthCenterPageState();
}

class _CloudDriveAuthCenterPageState extends State<CloudDriveAuthCenterPage> {
  late final CloudDriveAuthController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CloudDriveAuthController();
    _controller.load();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _handleAction(CloudDriveAccount account, String action) {
    final void Function(CloudDriveAccount, String)? callback = widget.onAction;
    if (callback != null) {
      callback(account, action);
      return;
    }
    VboxToast.show(context, '「$action」授权入口建设中');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('网盘账号授权'),
        actions: <Widget>[
          // 临时入口：网盘排序在 iOS 属「我的」页宫格（批次 I 落地），
          // 此处先以顶栏图标暴露，供 F-06 排序弹窗可达（迁移成本为零）。
          IconButton(
            tooltip: '网盘排序',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => CloudDriveSortPopup.show(context),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(
              '完成',
              style: TextStyle(
                fontSize: VboxTypography.s16,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? _) {
          if (_controller.loading && _controller.accounts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<CloudDriveAccount> accounts = _controller.accounts;
          return ListView(
            padding: const EdgeInsets.all(VboxSpacing.lg),
            children: <Widget>[
              VboxNodeStatusBanner(status: _controller.nodeStatus),
              for (final CloudDriveAccount account in accounts) ...<Widget>[
                const SizedBox(height: VboxSpacing.lg),
                VboxDriveAccountCard(
                  account: account,
                  onTest: () => _controller.testCredential(account.type),
                  onAction: (String action) => _handleAction(account, action),
                ),
              ],
              const SizedBox(height: VboxSpacing.lg),
              Text(
                '播放前不会强制检测授权状态；解析失败且像授权失效时才反向标记。手动粘贴入口继续保留为高级兜底。',
                style: TextStyle(
                  fontSize: VboxTypography.s12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
