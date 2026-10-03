/// 豆瓣首页（批次 D · D-03）。
///
/// 轮播横幅（TOP250 前若干）+ 区块横向列表（热门电影 / 剧集 / 综艺 / 动漫）。
/// 数据通路：[DoubanUseCases.homeFeed]（用例层并发拉取）。仅浏览，点击不跳转。
///
/// 结构：`DoubanHomePage`（独立页 = AppBar「豆瓣」+ [DoubanHomeView]）与
/// `VboxHomePage`（首页默认内容）**共用**同一 [DoubanHomeView]。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/douban/douban_models.dart';
import '../../../domain/usecases/douban_usecases.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/platform_async_image.dart';
import '../../widgets/vbox/vbox.dart';
import 'douban_widgets.dart';

/// 豆瓣独立页（AppBar「豆瓣」+ [DoubanHomeView]）。
class DoubanHomePage extends StatelessWidget {
  /// 构造。
  const DoubanHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('豆瓣')),
      body: const DoubanHomeView(),
    );
  }
}

/// 豆瓣首页内容视图（**不含** Scaffold / AppBar，供首页默认内容与独立页复用）。
class DoubanHomeView extends StatefulWidget {
  /// 构造。
  const DoubanHomeView({super.key});

  @override
  State<DoubanHomeView> createState() => _DoubanHomeViewState();
}

class _DoubanHomeViewState extends State<DoubanHomeView> {
  late final DoubanUseCases _uc;

  DoubanHomeFeed? _feed;
  Failure? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _uc = context.read<DoubanUseCases>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final Result<DoubanHomeFeed> result = await _uc.homeFeed();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = result.failureOrNull;
      _feed = result.valueOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Failure? error = _error;
    if (error != null) {
      return DoubanErrorRetry(message: '$error', onRetry: _load);
    }
    final DoubanHomeFeed? feed = _feed;
    if (feed == null || feed.isEmpty) {
      return const DoubanEmptyHint(text: '豆瓣暂无内容\n请稍后重试');
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.md),
      children: <Widget>[
        if (feed.banner.isNotEmpty) _buildBanner(feed.banner),
        for (final DoubanHomeSection section in feed.sections) _buildSection(section),
      ],
    );
  }

  Widget _buildBanner(List<DoubanSubject> items) {
    return _DoubanBanner(items: items);
  }

  Widget _buildSection(DoubanHomeSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VboxSectionHeader(title: section.title),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
            itemCount: section.items.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: VboxSpacing.md),
            itemBuilder: (BuildContext context, int index) =>
                DoubanSubjectCard(subject: section.items[index]),
          ),
        ),
      ],
    );
  }
}

/// 轮播横幅（海报 + 底部标题遮罩 + 页码指示）。
class _DoubanBanner extends StatefulWidget {
  const _DoubanBanner({required this.items});

  final List<DoubanSubject> items;

  @override
  State<_DoubanBanner> createState() => _DoubanBannerState();
}

class _DoubanBannerState extends State<_DoubanBanner> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 200,
          child: PageView.builder(
            itemCount: widget.items.length,
            onPageChanged: (int i) => setState(() => _page = i),
            itemBuilder: (BuildContext context, int i) {
              final DoubanSubject subject = widget.items[i];
              return Padding(
                padding: VboxSpacing.symmetric(horizontal: VboxSpacing.lg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      PlatformAsyncImage(url: subject.coverUrl, fit: BoxFit.cover),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(VboxSpacing.md),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.72),
                              ],
                            ),
                          ),
                          child: Text(
                            subject.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: VboxTypography.s16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: VboxSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < widget.items.length; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? scheme.primary : scheme.outlineVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}