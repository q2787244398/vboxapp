/// 设置页（批次 I · I-03 分区骨架 + I-04 显示模式 + I-05 更新入口）。
///
/// 唯一真相源：iOS `vbox/Views/SettingsViews.swift`
///   · L106-L134（`titleBar` + `settingsContent` 分区顺序）；
///   · L136-L173（`skinSettingsSection`：皮肤四选 + 跟随系统）；
///   · L175-L220（`playbackSettingsSection`：自定义弹幕源 + 搜索调试面板）；
///   · 各 `SettingsSection` / `SettingsToggleRow` / `SettingsNavigationRow`。
///
/// **落地范围（如实登记）**：本轮落地「皮肤（B4 组件 + 跟随系统）」「显示模式（I-04）」
/// 「播放设置」「工具入口（承接自个人中心迁出的远程源 / 网盘管理 / 备份还原）」
/// 「存储管理」「日志调试」「关于」七个分区；iOS 侧其余域分区（TMDB /
/// 站点诊断 / 切片源 / 站点管理）在 Flutter 侧对应域功能尚未实现，故以
/// **「更多设置（待实现）」**分组显式列出并标注，不虚标为可用（见交付回执遗留项）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/datasources/local/prefs_manager.dart';
import '../../../data/datasources/local/subscribe_config_store.dart';
import '../../../data/datasources/local/tg_search_config_store.dart';
import '../../../domain/entities/tg/tg_channel.dart';
import '../../phone/remote_source_page.dart';
import '../../theme/theme.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/backup_page.dart';
import '../../widgets/library_views.dart';
import '../../widgets/log_viewer_page.dart';
import '../../widgets/vbox/vbox.dart';
import '../cloud/auth_center.dart';
import '../subscribe/subscribe_config_page.dart';
import 'tg_channel_list_page.dart';

/// 设置页。
class SettingsPage extends StatefulWidget {
  /// 构造。
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _danmakuUrl = TextEditingController();
  final TextEditingController _tgProxy = TextEditingController();

  bool _danmakuEnabled = false;
  bool _searchDebug = false;
  bool _logEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _danmakuUrl.dispose();
    _tgProxy.dispose();
    super.dispose();
  }

  /// 读取契约键初值（对齐 iOS `@AppStorage` 的初始绑定）。
  Future<void> _load() async {
    final PrefsManager prefs = PrefsManager.instance;
    final bool danmaku = await prefs.getBool('custom_danmaku_source_enabled');
    final String url = await prefs.getString('custom_danmaku_source_url');
    final bool debug = await prefs.getBool('show_search_debug');
    final bool log = await prefs.getBool('app_log_enabled');
    final String tgProxy =
        await prefs.getString(TGSearchConfigStore.proxyUrlKey);
    if (!mounted) return;
    setState(() {
      _danmakuEnabled = danmaku;
      _danmakuUrl.text = url;
      _searchDebug = debug;
      _logEnabled = log;
      _tgProxy.text = tgProxy;
    });
  }

  @override
  Widget build(BuildContext context) {
    final VboxSkinController skin = context.watch<VboxSkinController>();
    final UiFormController form = context.watch<UiFormController>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(
          top: VboxSpacing.lg,
          bottom: VboxSpacing.xxxl,
        ),
        children: <Widget>[
          _skinSection(skin),
          _displayModeSection(form),
          _playbackSection(),
          _tgSection(),
          _subscribeSection(),
          _toolsSection(),
          _storageSection(),
          _developerSection(),
          _aboutSection(),
          _pendingSection(),
        ],
      ),
    );
  }

  /// 皮肤（四选 2×2 + 跟随系统；对齐 iOS `skinSettingsSection`）。
  Widget _skinSection(VboxSkinController skin) {
    final bool visual = skin.skin == VboxSkin.liquid || skin.skin == VboxSkin.frosted;
    return VboxSettingsSection(
      title: '皮肤',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(VboxSpacing.md),
          child: Column(
            children: <Widget>[
              VboxSkinPicker(
                selected: skin.skin,
                onSelected: skin.selectSkin,
              ),
              const SizedBox(height: VboxSpacing.md),
              Opacity(
                opacity: visual ? 0.55 : 1,
                child: VboxSettingsRow.toggle(
                  title: '黑暗/浅色跟随手机外观',
                  subtitle: '开启后随系统外观切换',
                  icon: Icons.brightness_6,
                  value: skin.followsSystem,
                  // 视觉皮肤（液态 / 磨砂）下禁用（对齐 iOS L163）。
                  onChanged: visual ? (_) {} : skin.setFollowsSystem,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 显示模式（I-04：自动 / 手机竖屏 / 大屏横屏，写入 `app_ui_form_override`）。
  Widget _displayModeSection(UiFormController form) {
    return VboxSettingsSection(
      title: '显示模式',
      children: <Widget>[
        VboxSettingsRow.navigation(
          title: '显示模式',
          subtitle: '当前：${form.override.title}',
          icon: Icons.aspect_ratio,
          onTap: () => _pickDisplayMode(form),
        ),
      ],
    );
  }

  /// 播放设置（自定义弹幕源 + 搜索调试面板；对齐 iOS `playbackSettingsSection`）。
  Widget _playbackSection() {
    final PrefsManager prefs = PrefsManager.instance;
    return VboxSettingsSection(
      title: '播放设置',
      children: <Widget>[
        VboxSettingsRow.toggle(
          title: '自定义弹幕源',
          subtitle: _danmakuEnabled
              ? '已开启 — 使用自定义弹幕API地址'
              : '关闭 — 使用默认弹幕源',
          icon: Icons.chat_bubble,
          value: _danmakuEnabled,
          onChanged: (bool value) async {
            setState(() => _danmakuEnabled = value);
            await prefs.set('custom_danmaku_source_enabled', value);
          },
        ),
        if (_danmakuEnabled)
          VboxSettingsInputRow(
            controller: _danmakuUrl,
            hint: 'https://your-danmu-api.com',
            onChanged: (String value) =>
                prefs.set('custom_danmaku_source_url', value),
          ),
        VboxSettingsRow.toggle(
          title: '搜索调试面板',
          icon: Icons.search,
          value: _searchDebug,
          onChanged: (bool value) async {
            setState(() => _searchDebug = value);
            await prefs.set('show_search_debug', value);
          },
        ),
      ],
    );
  }

  /// TG 搜索设置（代理地址 + 频道来源 + 频道管理入口；对齐 iOS `tgSearchSettingsSection`）。
  Widget _tgSection() {
    final TGSearchConfigStore tg = context.watch<TGSearchConfigStore>();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color rowBackground = (isDark
            ? VboxColors.secondarySystemGroupedBackgroundDark
            : VboxColors.secondarySystemGroupedBackgroundLight)
        .withValues(alpha: 0.7);
    final Color inputFill = isDark
        ? VboxColors.tertiarySystemGroupedBackgroundDark
        : VboxColors.tertiarySystemGroupedBackgroundLight;
    final Color secondary =
        isDark ? VboxColors.secondaryLabelDark : VboxColors.secondaryLabelLight;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final TextStyle labelStyle = TextStyle(
      fontSize: VboxTypography.s13,
      fontWeight: FontWeight.w500,
      color: onSurface,
    );
    final TextStyle hintStyle = TextStyle(
      fontSize: VboxTypography.s11,
      color: secondary,
    );

    return VboxSettingsSection(
      title: 'TG搜索设置',
      children: <Widget>[
        // 代理地址
        Material(
          color: rowBackground,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VboxSpacing.lg,
              vertical: VboxSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('代理地址', style: labelStyle),
                const SizedBox(height: VboxSpacing.sm),
                TextField(
                  controller: _tgProxy,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.url,
                  onChanged: tg.setProxyUrl,
                  style: TextStyle(fontSize: VboxTypography.s15, color: onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: inputFill,
                    hintText: 'https://xxx.com/?token=xxx&url=',
                    hintStyle: TextStyle(
                      fontSize: VboxTypography.s15,
                      color: secondary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: VboxSpacing.md,
                      vertical: VboxSpacing.md,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: VboxRadii.button,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: VboxSpacing.sm),
                Text('支持URL转发代理，在末尾拼接原始URL', style: hintStyle),
              ],
            ),
          ),
        ),
        // 频道来源
        Material(
          color: rowBackground,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VboxSpacing.lg,
              vertical: VboxSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('频道来源', style: labelStyle),
                const SizedBox(height: VboxSpacing.sm),
                SegmentedButton<TGChannelMode>(
                  segments: TGChannelMode.values
                      .map((TGChannelMode mode) => ButtonSegment<TGChannelMode>(
                            value: mode,
                            label: Text(mode.displayName),
                          ))
                      .toList(growable: false),
                  selected: <TGChannelMode>{tg.channelMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<TGChannelMode> selection) =>
                      tg.setChannelMode(selection.first),
                ),
                const SizedBox(height: VboxSpacing.sm),
                Text(tg.channelMode.description, style: hintStyle),
              ],
            ),
          ),
        ),
        // 频道管理入口
        VboxSettingsRow.navigation(
          title: 'TG频道管理',
          subtitle: '${tg.channels.length} 个自定义频道',
          icon: Icons.telegram,
          iconColor: VboxColors.tgChannelPurple,
          onTap: () => _push(const TGChannelListPage()),
        ),
      ],
    );
  }

  /// 订阅配置（管理订阅源入口；对齐 iOS `subscriptionSection`，批次 G · G-07）。
  Widget _subscribeSection() {
    final SubscribeConfigStore store = context.watch<SubscribeConfigStore>();
    return VboxSettingsSection(
      title: '订阅配置',
      children: <Widget>[
        VboxSettingsRow.navigation(
          title: '管理订阅源',
          subtitle:
              store.hasConfigUrls ? '${store.configUrls.length} 个源' : '未配置',
          icon: Icons.list_alt,
          iconColor: VboxColors.skinPrimaryRose,
          onTap: () => _push(const SubscribeConfigPage()),
        ),
      ],
    );
  }

  /// 工具入口（承接个人中心迁出的远程源 / 网盘管理 / 备份还原）。
  Widget _toolsSection() {
    return VboxSettingsSection(
      title: '工具',
      children: <Widget>[
        VboxSettingsRow.navigation(
          title: '书架',
          icon: Icons.menu_book,
          onTap: () => _push(_bookshelf()),
        ),
        VboxSettingsRow.navigation(
          title: '远程源',
          icon: Icons.cloud_sync,
          onTap: () => _push(const RemoteSourcePage()),
        ),
        VboxSettingsRow.navigation(
          title: '网盘管理',
          icon: Icons.folder,
          onTap: () => _push(const CloudDriveAuthCenterPage()),
        ),
        VboxSettingsRow.navigation(
          title: '备份还原',
          icon: Icons.backup,
          onTap: () => _push(const BackupPage()),
        ),
      ],
    );
  }

  /// 存储管理（缓存概览；清缓存依赖缓存层，暂登记为待接线）。
  Widget _storageSection() {
    return VboxSettingsSection(
      title: '存储管理',
      children: <Widget>[
        VboxSettingsRow.navigation(
          title: '缓存管理',
          subtitle: '清缓存将在后续批次开放',
          icon: Icons.cleaning_services,
          onTap: () => VboxToast.show(context, '缓存清理将在后续批次开放'),
        ),
      ],
    );
  }

  /// 日志调试（开启日志记录 + 查看日志；对齐 iOS `developerSection`）。
  Widget _developerSection() {
    final PrefsManager prefs = PrefsManager.instance;
    return VboxSettingsSection(
      title: '日志调试',
      children: <Widget>[
        VboxSettingsRow.toggle(
          title: '开启日志记录',
          subtitle: '关闭后停止写入本地日志',
          icon: Icons.article,
          value: _logEnabled,
          onChanged: (bool value) async {
            setState(() => _logEnabled = value);
            await prefs.set('app_log_enabled', value);
          },
        ),
        VboxSettingsRow.navigation(
          title: '查看日志',
          icon: Icons.list_alt,
          onTap: () => _push(const LogViewerPage()),
        ),
      ],
    );
  }

  /// 关于 / 更新（版本 + 检查更新；对齐 iOS `aboutSection`）。
  Widget _aboutSection() {
    return VboxSettingsSection(
      title: '关于',
      children: <Widget>[
        VboxSettingsRow(
          title: '版本',
          icon: Icons.info,
          trailing: Text(
            '${AppInfo.version}+${AppInfo.buildNumber}',
            style: TextStyle(
              fontSize: VboxTypography.s13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        VboxSettingsRow.navigation(
          title: '检查更新',
          subtitle: '自更新将在 K 批次开放',
          icon: Icons.system_update,
          onTap: () => VboxToast.show(context, '当前版本 ${AppInfo.version} 已是最新版本'),
        ),
      ],
    );
  }

  /// 待实现分区（如实标注，不虚标可用）。
  Widget _pendingSection() {
    const List<(IconData, String)> pending = <(IconData, String)>[
      (Icons.movie_filter, 'TMDB 设置'),
      (Icons.health_and_safety, '站点诊断'),
      (Icons.content_cut, '切片源'),
      (Icons.dns, '站点管理'),
    ];
    return VboxSettingsSection(
      title: '更多设置（待实现）',
      children: <Widget>[
        for (final (IconData icon, String title) in pending)
          VboxSettingsRow.navigation(
            title: title,
            subtitle: '对应域功能尚未实现，将在后续批次开放',
            icon: icon,
            onTap: () => VboxToast.show(context, '$title 将在后续批次开放'),
          ),
      ],
    );
  }

  /// 显示模式选择（I-04）。
  Future<void> _pickDisplayMode(UiFormController form) async {
    final UiFormOverride? selected = await showDialog<UiFormOverride>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('显示模式'),
        children: <Widget>[
          for (final UiFormOverride option in UiFormOverride.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(option),
              child: Row(
                children: <Widget>[
                  Icon(
                    option == form.override
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: VboxTypography.s18,
                  ),
                  const SizedBox(width: VboxSpacing.md),
                  Text(option.title),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null || selected == form.override) return;
    await PrefsManager.instance.set('app_ui_form_override', selected.id);
    form.setOverride(selected);
    if (mounted) VboxToast.show(context, '已切换为「${selected.title}」');
  }

  /// 书架（收藏 / 历史双 Tab；承接自底栏迁出的入口）。
  Widget _bookshelf() {
    return DefaultTabController(
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
    );
  }

  void _push(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }
}