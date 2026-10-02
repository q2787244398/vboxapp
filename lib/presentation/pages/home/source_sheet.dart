/// 切换源浮层（批次 D · D-01）。
///
/// 底部弹出（圆角 + 拖拽手柄 + 阴影），列出全部可浏览站点；点击某源关闭并返回
/// 其 `key`，由调用方据此重载首页内容。选中态高亮当前源。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/spider/spider.dart';
import '../../theme/tokens/typography.dart';

/// 弹出切换源浮层，返回选中的站点 key（取消返回 null）。
Future<String?> showVboxSourceSheet(
  BuildContext context, {
  required List<SiteConfig> sites,
  String? selectedKey,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => _SourceSheet(
      sites: sites,
      selectedKey: selectedKey,
    ),
  );
}

/// 浮层内容。
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.sites, this.selectedKey});

  final List<SiteConfig> sites;
  final String? selectedKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '切换源 ${sites.length}',
                style: TextStyle(
                  fontSize: VboxTypography.s18,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sites.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final SiteConfig site = sites[index];
                  final bool selected = site.key == selectedKey;
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.public,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(
                      site.name.isEmpty ? site.key : site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      site.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle, color: scheme.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(site.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}