/// 「个人中心（我的）」页面（批次 A8 + I-01）。
///
/// 唯一真相源：iOS `ProfileView.swift` L259-L338（`loginSection`）·
/// L342-L406（`watchHistorySection`）· L413-L485（`featureEntriesSection`）·
/// L488-L502（`featureButton`）。
///
/// 版式：顶栏（左分享 / 右设置）→ 居中圆形头像 + 昵称 + 账号 →
/// 观看记录分区（主色竖条标题 + 「查看更多 >」+ 横向海报）→ 3×3 功能宫格 →
/// 「更多工具」入口分组。头部**不是**主色渐变卡（以 iOS 截图为准）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/result.dart';
import '../../../domain/entities/library/library.dart';
import '../../../domain/usecases/usecases.dart';
import '../../phone/remote_source_page.dart';
import '../../theme/brand.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/backup_page.dart';
import '../../widgets/library_views.dart';
import '../../widgets/log_viewer_page.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import '../cloud/auth_center.dart';
import '../cloud/sort.dart';
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
          _topBar(context, scheme),
          const SizedBox(height: VboxSpacing.xl),
          _header(scheme),
          const SizedBox(height: VboxSpacing.xxl),
          _historyHeader(context, scheme),
          const SizedBox(height: VboxSpacing.md),
          const _WatchHistorySection(
            posterWidth: _posterWidth,
            posterHeight: _posterHeight,
          ),
          const SizedBox(height: VboxSpacing.xxl),
          _featureGrid(context),
          const SizedBox(height: VboxSpacing.xxl),
          const VboxSectionHeader(title: '更多工具'),
          _moreTools(context, scheme),
        ],
      ),
    );
  }

  /// 顶栏：左分享 · 右设置（均主色）。
  Widget _topBar(BuildContext context, ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        IconButton(
          tooltip: '分享',
          onPressed: () => VboxToast.show(context, '分享链接已复制'),
          icon: Icon(Icons.ios_share, color: scheme.primary),
        ),
        IconButton(
          tooltip: '设置',
          onPressed: () => VboxToast.show(context, '设置页将在 I-03 批次开放'),
          icon: Icon(Icons.settings, color: scheme.primary),
        ),
      ],
    );
  }

  /// 头部：居中圆形头像 + 昵称（含铅笔）+ 账号说明。
  Widget _header(ColorScheme scheme) {
    const double radius = _avatarSize / 2;
    return Column(
      children: <Widget>[
        ClipOval(
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
        ),
        const SizedBox(height: VboxSpacing.md),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'vbox 默认账号',
              style: TextStyle(
                fontSize: VboxTypography.s18,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: VboxSpacing.xs),
            Icon(
              Icons.edit,
              size: VboxTypography.s12,
              color: scheme.outline,
            ),
          ],
        ),
        const SizedBox(height: VboxSpacing.xs),
        Text(
          '账号： 199114',
          style: TextStyle(
            fontSize: VboxTypography.s12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
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

  /// 3×3 功能宫格（顺序对齐 iOS `featureEntriesSection`）。
  Widget _featureGrid(BuildContext context) {
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
          onTap: () => VboxToast.show(context, '推送播放将在后续批次开放'),
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

  /// 「更多工具」入口分组（承接 A8 从底栏移除的入口，避免功能失去入口）。
  Widget _moreTools(BuildContext context, ColorScheme scheme) {
    return Column(
      children: <Widget>[
        _toolRow(
          context,
          scheme,
          icon: Icons.menu_book,
          title: '书架',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => DefaultTabController(
                  length: 2,
                  child: Scaffold(
                    appBar: AppBar(
                      title: const Text('书架'),
                      bottom: const TabBar(
                        tabs: <Widget>[
                          Tab(text: '收藏'),
                          Tab(text: '历史'),
                        ],
                      ),
                    ),
                    body: const TabBarView(
                      children: <Widget>[
                        FavoritesView(),
                        HistoryView(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        _toolRow(
          context,
          scheme,
          icon: Icons.cloud_sync,
          title: '远程源',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const RemoteSourcePage(),
              ),
            );
          },
        ),
        const Divider(height: 1),
        _toolRow(
          context,
          scheme,
          icon: Icons.folder,
          title: '网盘管理',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    const CloudDriveAuthCenterPage(),
              ),
            );
          },
        ),
        const Divider(height: 1),
        _toolRow(
          context,
          scheme,
          icon: Icons.bug_report_outlined,
          title: '日志调试',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const LogViewerPage(),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 单行入口：左小图标 + 标题 + 右箭头。
  Widget _toolRow(
    BuildContext context,
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: VboxSpacing.symmetric(vertical: VboxSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(icon, size: VboxTypography.s18, color: scheme.primary),
            const SizedBox(width: VboxSpacing.md),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: VboxTypography.s15,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 观看记录横向海报（直连 [HistoryUseCases]，对齐 `library_views.dart` 的加载方式）。
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
    final List<HistoryItem> items = _items;
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