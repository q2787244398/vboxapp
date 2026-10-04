/// 「个人中心（我的）」页面（批次 A8 + I-01 + I-02）。
///
/// 唯一真相源：iOS `ProfileView.swift`
///   · L106-L244（`body`：ZStack 顶栏 + 三段内容 + 各 sheet）；
///   · L259-L338（`loginSection`：头像 + 展示名 + 账号 / 点击登录）；
///   · L342-L406（`watchHistorySection`）；
///   · L413-L502（`featureEntriesSection` + `featureButton`）；
///   · L808-L839（`loadInitialState` / `performLogout`）· L1072-L1125（登录）。
///
/// 版式：顶栏（**左退出**（仅登录态）/ **右设置**）→ 居中圆形头像 + 展示名（登录态可改名）
/// + 账号说明 / 点击登录 → 观看记录分区（主色竖条标题 + 「查看更多 >」+ 横向海报）→
/// 3×3 功能宫格（「备份还原」仅登录态显示）。
///
/// 说明：原「更多工具」分组已移除 —— 书架 / 远程源 / 网盘管理 / 日志调试均迁入
/// [SettingsPage]（对齐 iOS：这些入口在设置页内，不进个人中心）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/result.dart';
import '../../../domain/entities/library/library.dart';
import '../../../domain/usecases/usecases.dart';
import '../../profile/session_controller.dart';
import '../../theme/brand.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../welfare/welfare_controller.dart';
import '../../widgets/backup_page.dart';
import '../../widgets/library_views.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import '../cloud/sort.dart';
import '../push/push_play_page.dart';
import '../settings/settings_page.dart';
import 'welfare_sheet.dart';

/// 「个人中心（我的）」页。
class ProfilePage extends StatelessWidget {
  /// 构造。
  const ProfilePage({super.key});

  /// 头像直径（对齐 iOS `frame(width: 80, height: 80)`）。
  static const double _avatarSize = 80;

  /// 观看记录海报宽（对齐 iOS `frame(width: 100)`）。
  static const double _posterWidth = 100;

  /// 观看记录海报高（对齐 iOS `frame(height: 140)`）。
  static const double _posterHeight = 140;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SessionController session = context.watch<SessionController>();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          VboxSpacing.lg,
          VboxSpacing.xl,
          VboxSpacing.lg,
          // 底部预留悬浮 TabBar 空间（约 100）。
          VboxSpacing.xxxl * 3 + VboxSpacing.xs,
        ),
        children: <Widget>[
          _topBar(context, scheme, session),
          const SizedBox(height: VboxSpacing.xl),
          _header(context, scheme, session),
          const SizedBox(height: VboxSpacing.xxl),
          _historyHeader(context, scheme),
          const SizedBox(height: VboxSpacing.md),
          const _WatchHistorySection(
            posterWidth: _posterWidth,
            posterHeight: _posterHeight,
          ),
          const SizedBox(height: VboxSpacing.xxl),
          _featureGrid(context, session),
        ],
      ),
    );
  }

  /// 顶栏：左「退出」（仅登录态显示）· 右「设置」（对齐 iOS L174-L199）。
  Widget _topBar(
    BuildContext context,
    ColorScheme scheme,
    SessionController session,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        if (session.isLoggedIn)
          IconButton(
            tooltip: '退出登录',
            onPressed: () => _confirmLogout(context, session),
            icon: Icon(Icons.logout, color: scheme.primary),
          )
        else
          const SizedBox(width: VboxSpacing.xxxl),
        IconButton(
          tooltip: '设置',
          onPressed: () => _openSettings(context),
          icon: Icon(Icons.settings, color: scheme.primary),
        ),
      ],
    );
  }

  /// 头部：居中头像 + 展示名（登录态带铅笔）+ 账号说明 / 点击登录。
  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    SessionController session,
  ) {
    return Column(
      children: <Widget>[
        GestureDetector(
          onTap: () => VboxToast.show(context, '头像更换将在后续批次开放'),
          child: _avatar(scheme, session),
        ),
        const SizedBox(height: VboxSpacing.md),
        GestureDetector(
          onTap: session.isLoggedIn
              ? () => _openRename(context, session)
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                session.displayName,
                style: TextStyle(
                  fontSize: VboxTypography.s18,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (session.isLoggedIn) ...<Widget>[
                const SizedBox(width: VboxSpacing.xs),
                Icon(
                  Icons.edit,
                  size: VboxTypography.s12,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: VboxSpacing.xs),
        if (session.isLoggedIn)
          Text(
            '账号：${session.account}',
            style: TextStyle(
              fontSize: VboxTypography.s12,
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          TextButton(
            onPressed: () => _openLogin(context, session),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: VboxSpacing.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '点击登录',
              style: TextStyle(fontSize: VboxTypography.s15),
            ),
          ),
      ],
    );
  }

  /// 头像：已存头像 → 展示名首字母圈 → 未登录回退软件图标。
  Widget _avatar(ColorScheme scheme, SessionController session) {
    const double radius = _avatarSize / 2;
    final String? base64 = session.avatarBase64;
    if (session.isLoggedIn && base64 != null && base64.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          base64Decode(base64),
          width: _avatarSize,
          height: _avatarSize,
          fit: BoxFit.cover,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) =>
                  _letterAvatar(scheme, session),
        ),
      );
    }
    if (session.isLoggedIn && session.username.isNotEmpty) {
      return _letterAvatar(scheme, session);
    }
    return ClipOval(
      child: Image.asset(
        VboxBrand.splashLogoAsset,
        width: _avatarSize,
        height: _avatarSize,
        fit: BoxFit.cover,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                CircleAvatar(
          radius: radius,
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(
            Icons.person,
            size: VboxTypography.s24,
            color: scheme.outline,
          ),
        ),
      ),
    );
  }

  /// 首字母头像（对齐 iOS 未设置头像时的灰圈 + 首字母）。
  Widget _letterAvatar(ColorScheme scheme, SessionController session) {
    final String name = session.username.isEmpty ? session.account : session.username;
    final String letter = name.isEmpty ? '?' : name.substring(0, 1);
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: VboxTypography.s28,
          fontWeight: FontWeight.w700,
          color: scheme.outline,
        ),
      ),
    );
  }

  /// 观看记录分区标题行（主色竖条 + 标题 + 查看更多）。
  Widget _historyHeader(BuildContext context, ColorScheme scheme) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: VboxSpacing.lg,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: VboxRadii.badge,
          ),
        ),
        const SizedBox(width: VboxSpacing.sm),
        Text(
          '观看记录',
          style: TextStyle(
            fontSize: VboxTypography.s16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => VboxToast.show(context, '观看记录将在后续批次开放'),
          child: Text(
            '查看更多 >',
            style: TextStyle(fontSize: VboxTypography.s12, color: scheme.outline),
          ),
        ),
      ],
    );
  }

  /// 3×3 功能宫格（顺序对齐 iOS `featureEntriesSection`；「备份还原」仅登录态）。
  Widget _featureGrid(BuildContext context, SessionController session) {
    return VboxQuickGrid(
      items: <VboxQuickGridItem>[
        VboxQuickGridItem(
          icon: Icons.card_giftcard,
          label: '福利专区',
          onTap: () => showVboxWelfareSheet(context),
        ),
        VboxQuickGridItem(
          icon: Icons.star,
          label: '我的收藏',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => Scaffold(
                  appBar: AppBar(title: const Text('我的收藏')),
                  body: const FavoritesView(),
                ),
              ),
            );
          },
        ),
        VboxQuickGridItem(
          icon: Icons.smart_display,
          label: '推送播放',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const PushPlayPage(),
              ),
            );
          },
        ),
        VboxQuickGridItem(
          icon: Icons.ios_share,
          label: '分享vbox',
          onTap: () => VboxToast.show(context, '分享链接已复制'),
        ),
        VboxQuickGridItem(
          icon: Icons.download,
          label: '下载管理',
          onTap: () => VboxToast.show(context, '下载管理将在后续批次开放'),
        ),
        VboxQuickGridItem(
          icon: Icons.swap_vert,
          label: '网盘排序',
          onTap: () => CloudDriveSortPopup.show(context),
        ),
        // 备份还原仅登录态显示（对齐 iOS L465）。
        if (session.isLoggedIn)
          VboxQuickGridItem(
            icon: Icons.backup,
            label: '备份还原',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const BackupPage(),
                ),
              );
            },
          ),
        VboxQuickGridItem(
          icon: Icons.music_note,
          label: '网络音乐',
          onTap: () => VboxToast.show(context, '网络音乐将在后续批次开放'),
        ),
        VboxQuickGridItem(
          icon: Icons.bug_report,
          label: 'Bug反馈',
          onTap: () => VboxToast.show(context, 'Bug 反馈将在 G-09 批次开放'),
        ),
      ],
    );
  }

  /// 打开设置页（右上角齿轮）。
  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SettingsPage(),
      ),
    );
  }

  /// 登录弹窗（对齐 iOS `LoginSheetView`）。
  Future<void> _openLogin(
    BuildContext context,
    SessionController session,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => _LoginSheetHost(session: session),
    );
  }

  /// 修改展示名（仅改展示名，不影响登录账号）。
  Future<void> _openRename(
    BuildContext context,
    SessionController session,
  ) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext _) => _RenameDialog(initial: session.username),
    );
    if (name != null) await session.rename(name);
  }

  /// 退出确认（对齐 iOS `.alert("退出登录")`）。
  Future<void> _confirmLogout(
    BuildContext context,
    SessionController session,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新输入账号密码登录，本机已保存的密码不会删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await session.logout();
  }
}

/// 登录弹窗宿主：管理输入控制器 / 错误 / 加载态并驱动 [SessionController]。
class _LoginSheetHost extends StatefulWidget {
  const _LoginSheetHost({required this.session});

  final SessionController session;

  @override
  State<_LoginSheetHost> createState() => _LoginSheetHostState();
}

class _LoginSheetHostState extends State<_LoginSheetHost> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _username.addListener(_refreshRegistered);
  }

  @override
  void dispose() {
    _username.removeListener(_refreshRegistered);
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 输入变化时刷新「登录 / 注册」按钮文案（对齐 iOS `isRegistered`）。
  Future<void> _refreshRegistered() async {
    final bool registered = await widget.session.isRegistered(_username.text);
    if (!mounted || registered == _registered) return;
    setState(() => _registered = registered);
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final String? error = await widget.session.login(
      account: _username.text,
      password: _password.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _error = error;
        _loading = false;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return VboxLoginSheet(
      usernameController: _username,
      passwordController: _password,
      onSubmit: _submit,
      onCancel: () => Navigator.of(context).pop(),
      error: _error,
      loading: _loading,
      registered: _registered,
    );
  }
}

/// 修改展示名弹窗（对齐 iOS `EditNicknameSheet`）。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VboxDialog(
      title: '修改用户名',
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
      child: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '请输入新的用户名'),
      ),
    );
  }
}

/// 观看记录横向海报（直连 [HistoryUseCases]；福利关闭时过滤 `[福利]` 记录，R-10）。
class _WatchHistorySection extends StatefulWidget {
  const _WatchHistorySection({
    required this.posterWidth,
    required this.posterHeight,
  });

  final double posterWidth;
  final double posterHeight;

  @override
  State<_WatchHistorySection> createState() => _WatchHistorySectionState();
}

class _WatchHistorySectionState extends State<_WatchHistorySection> {
  // 用例引用在 initState 缓存，避免跨 async gap 使用 context
  late final HistoryUseCases _useCases;
  List<HistoryItem> _items = const <HistoryItem>[];

  @override
  void initState() {
    super.initState();
    _useCases = context.read<HistoryUseCases>();
    _load();
  }

  Future<void> _load() async {
    final Result<List<HistoryItem>> result =
        await _useCases.recent(limit: HistoryUseCases.defaultLimit);
    if (!mounted) return;
    setState(() {
      _items = result.valueOrNull ?? const <HistoryItem>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // R-10：关闭福利总开关后隐藏福利观看记录（对齐 iOS reloadHistory 的过滤）。
    final bool welfareEnabled = context.watch<WelfareController>().enabled;
    final List<HistoryItem> items = welfareEnabled
        ? _items
        : _items
            .where((HistoryItem h) => !h.laiyuan.startsWith('[福利]'))
            .toList(growable: false);
    if (items.isEmpty) {
      return Text(
        '暂无观看记录',
        style: TextStyle(fontSize: VboxTypography.s14, color: scheme.outline),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: VboxSpacing.md),
            _poster(scheme, items[i]),
          ],
        ],
      ),
    );
  }

  Widget _poster(ColorScheme scheme, HistoryItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: VboxRadii.button,
          child: SizedBox(
            width: widget.posterWidth,
            height: widget.posterHeight,
            child: PlatformAsyncImage(url: item.imgurl),
          ),
        ),
        const SizedBox(height: VboxSpacing.xs),
        SizedBox(
          width: widget.posterWidth,
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: VboxTypography.s12,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}