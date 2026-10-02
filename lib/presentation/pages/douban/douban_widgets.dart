/// 豆瓣浏览页共享组件（批次 D · D-03）。
///
/// 跨三页（首页 / 榜单 / 分类）复用的海报卡与空态 / 错误态，避免三处重复实现。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/douban/douban_models.dart';
import '../../theme/tokens/spacing.dart';
import '../../widgets/vbox/vbox.dart';

/// 评分文案（无评分 → null）。
String? doubanRatingText(DoubanSubject subject) =>
    subject.hasRating ? subject.rating.toStringAsFixed(1) : null;

/// 副标题文案（年份 · 类型，均空 → null）。
String? doubanSubtitle(DoubanSubject subject) {
  final String text = <String?>[
    subject.year,
    if (subject.genreText.isNotEmpty) subject.genreText,
  ].whereType<String>().join(' · ');
  return text.isEmpty ? null : text;
}

/// 豆瓣条目海报卡（封面 + 标题 + 评分角标 + 副标题）。
class DoubanSubjectCard extends StatelessWidget {
  /// 构造。
  const DoubanSubjectCard({
    super.key,
    required this.subject,
    this.width = 120,
    this.onTap,
  });

  final DoubanSubject subject;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VboxPosterCard(
      title: subject.title,
      imageUrl: subject.coverUrl,
      subtitle: doubanSubtitle(subject),
      rating: doubanRatingText(subject),
      width: width,
      onTap: onTap,
    );
  }
}

/// 空态提示。
class DoubanEmptyHint extends StatelessWidget {
  /// 构造。
  const DoubanEmptyHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ),
    );
  }
}

/// 加载失败提示 + 重试。
class DoubanErrorRetry extends StatelessWidget {
  /// 构造。
  const DoubanErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: VboxSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: VboxSpacing.md),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}