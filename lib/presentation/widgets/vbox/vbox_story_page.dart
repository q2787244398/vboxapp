/// 统一组件库 · Story 页（批次 A · A-04 验收项）。
///
/// 唯一真相源：`docs/第2轮细分实施WBS_v1.3.md` A-04「组件 Story 页 + 单测；
/// 规格对齐 UI 基准」。
///
/// 用途：**组件总览画廊**（living style guide）——一页陈列全部 A-04 组件的
/// 代表形态，供：
///   1. 视觉核对（对照 `docs/ui_baseline/01_tokens.png` 规格图）；
///   2. Golden 基线（本页已入 `test/golden`，令牌/规格漂移当场像素失败）；
///   3. 后续页面开发的组件选型参考。
///
/// 注：仅开发/验收用，不接入路由（真机验收走 Golden + 单测）。
library;

import 'package:flutter/material.dart';

import '../../theme/brand.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/radii.dart';
import 'vbox.dart';

/// 组件 Story 页（全组件画廊）。
class VboxStoryPage extends StatelessWidget {
  /// 构造。
  const VboxStoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VboxStoryView();
  }
}

class VboxStoryView extends StatelessWidget {
  const VboxStoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('组件 Story · A-04')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _section('品牌（A-13）', _brand()),
          _section('按钮 Button', _buttons()),
          _section('卡片 Card', _cards()),
          _section('胶囊 Chip / 剧集 EpisodeChip', _chips()),
          _section('区块标题 SectionHeader', const _SectionHeaders()),
          _section('源角标 SourceBadge', _badges()),
          _section('海报卡 PosterCard', _posters()),
          _section('导航 BottomNav / NavRail', const _NavDemo()),
          _section('浮层 Dialog / Toast', const _OverlayDemo()),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          VboxSectionHeader(title: title),
          const SizedBox(height: 8),
          child,
          const SizedBox(height: 24),
        ],
      );

  Widget _brand() => const Row(
        children: <Widget>[
          _BrandMark(),
          SizedBox(width: 12),
          Text(
            VboxBrand.wordmark,
            style: TextStyle(
              fontFamily: VboxBrand.fontFamily,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ],
      );

  Widget _buttons() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          const VboxButton(label: '主要'),
          VboxButton(
            label: '次要',
            kind: VboxButtonKind.secondary,
            onPressed: () {},
          ),
          VboxButton(
            label: '危险',
            kind: VboxButtonKind.danger,
            onPressed: () {},
          ),
        ],
      );

  Widget _cards() => const Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          SizedBox(
            width: 200,
            child: VboxCard(child: Text('大卡片 · 圆角 20（面板/主角）')),
          ),
          SizedBox(
            width: 200,
            child: VboxCard(
              radius: VboxRadii.r10,
              child: Text('中卡片 · 圆角 10（分组列表）'),
            ),
          ),
        ],
      );

  Widget _chips() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          VboxChip(label: '电影', onTap: () {}),
          const VboxChip(label: '剧集'),
          const VboxEpisodeChip(label: '01'),
          const VboxEpisodeChip(label: '02', selected: true),
        ],
      );

  Widget _badges() => const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          VboxSourceBadge.category(label: 'app', category: VboxCategory.app),
          VboxSourceBadge.category(label: 'spider', category: VboxCategory.spider),
          VboxSourceBadge.category(label: 'player', category: VboxCategory.player),
          VboxSourceBadge.category(label: 'cloud', category: VboxCategory.cloud),
          VboxSourceBadge.category(label: 'proxy', category: VboxCategory.proxy),
          VboxSourceBadge.category(label: 'network', category: VboxCategory.network),
          VboxSourceBadge.category(label: 'db', category: VboxCategory.db),
          VboxSourceBadge.category(label: 'download', category: VboxCategory.download),
        ],
      );

  Widget _posters() => SizedBox(
        height: 240,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: const <Widget>[
            VboxPosterCard(title: '示例剧集', subtitle: '2026 · 全 12 集'),
            VboxPosterCard(
              title: '带评分',
              subtitle: '2025',
              rating: '8.9',
            ),
            VboxPosterCard(title: '占位封面', subtitle: '2024'),
          ],
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      VboxBrand.splashLogoAsset,
      width: 56,
      height: 56,
      errorBuilder: (BuildContext context, Object e, StackTrace? s) =>
          const SizedBox(width: 56, height: 56),
    );
  }
}

class _SectionHeaders extends StatelessWidget {
  const _SectionHeaders();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VboxSectionHeader(title: '影院热映'),
        SizedBox(height: 8),
        VboxSectionHeader(title: '即将上映', subtitle: '本周上新'),
      ],
    );
  }
}

class _NavDemo extends StatelessWidget {
  const _NavDemo();

  @override
  Widget build(BuildContext context) {
    const List<VboxNavItem> items = <VboxNavItem>[
      VboxNavItem(icon: Icons.home_outlined, label: '首页'),
      VboxNavItem(icon: Icons.search, label: '搜索'),
      VboxNavItem(icon: Icons.video_library_outlined, label: '书架'),
    ];
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: 72, child: _BottomNavDemo(items: items)),
        SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: _RailDemo(items: items),
        ),
      ],
    );
  }
}

class _BottomNavDemo extends StatefulWidget {
  const _BottomNavDemo({required this.items});

  final List<VboxNavItem> items;

  @override
  State<_BottomNavDemo> createState() => _BottomNavDemoState();
}

class _BottomNavDemoState extends State<_BottomNavDemo> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return VboxBottomNav(
      items: widget.items,
      selectedIndex: _index,
      onSelected: (int i) => setState(() => _index = i),
    );
  }
}

class _RailDemo extends StatefulWidget {
  const _RailDemo({required this.items});

  final List<VboxNavItem> items;

  @override
  State<_RailDemo> createState() => _RailDemoState();
}

class _RailDemoState extends State<_RailDemo> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return VboxNavRail(
      items: widget.items,
      selectedIndex: _index,
      onSelected: (int i) => setState(() => _index = i),
    );
  }
}

class _OverlayDemo extends StatelessWidget {
  const _OverlayDemo();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        VboxButton(
          label: '打开 Dialog',
          onPressed: () => VboxDialog.show(
            context,
            title: '示例弹窗',
            child: const Text('VboxDialog · 居中卡片（圆角 14）'),
          ),
        ),
        VboxButton(
          label: '弹 Toast',
          onPressed: () => VboxToast.show(context, '已加入收藏'),
        ),
      ],
    );
  }
}