/// 网盘文件列表页（批次 F · F-07，对齐 iOS 播放链多文件列表 / 转存 / 清理队列）。
///
/// 结构：
/// - 顶栏「<网盘> 文件列表 + 刷新 / 清理队列」；
/// - 面包屑（根 = 网盘显示名，逐级进入子目录）；
/// - 文件 / 文件夹条目列表（文件夹优先，点击进入；文件点击转存并入清理队列）；
/// - 底部「清理队列」卡（待清理条数 + 立即清理）。
///
/// 数据由 [CloudDriveFilesController] 提供；目录列举缺省「未接入」直报错
/// （对齐 iOS A1 接缝未就绪行为），清理队列持久化契约键
/// `cloud_drive_cleanup_queue_v1`。
library;

import 'package:flutter/material.dart';

import '../../../data/datasources/local/cloud_drive_cleanup_queue_store.dart';
import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/cloud_drive_files.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/radii.dart';
import '../../theme/tokens/spacing.dart';
import '../../theme/tokens/typography.dart';
import '../../widgets/vbox/vbox.dart';
import 'cloud_drive_widgets.dart';
import 'files_controller.dart';

/// 网盘文件列表页。
class CloudDriveFilesPage extends StatefulWidget {
  /// 构造（[controller] 供测试注入；缺省自建并自管生命周期）。
  const CloudDriveFilesPage({
    super.key,
    required this.driveType,
    this.controller,
    this.lister,
    this.cleanupStore,
  });

  /// 目标网盘。
  final CloudDriveType driveType;

  /// 外部注入的控制器（null → 页面自建）。
  final CloudDriveFilesController? controller;

  /// 目录列举接缝（controller 为 null 时生效）。
  final CloudDriveFileLister? lister;

  /// 清理队列存储（controller 为 null 时生效）。
  final CloudDriveCleanupQueueStore? cleanupStore;

  @override
  State<CloudDriveFilesPage> createState() => _CloudDriveFilesPageState();
}

class _CloudDriveFilesPageState extends State<CloudDriveFilesPage> {
  late final CloudDriveFilesController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        CloudDriveFilesController(
          driveType: widget.driveType,
          lister: widget.lister,
          cleanupStore: widget.cleanupStore,
        );
    _controller.load();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _onBack() async {
    final bool moved = await _controller.goUp();
    if (!moved && mounted) Navigator.of(context).maybePop();
  }

  /// 文件点击：转存 + 入清理队列（去重）。
  Future<void> _onTransfer(CloudDriveFileEntry entry) async {
    final int added = await _controller.transferAndSchedule(
      <String>[entry.fileId],
    );
    if (!mounted) return;
    VboxToast.show(
      context,
      added > 0 ? '已转存并加入清理队列' : '该文件已在清理队列中',
    );
  }

  /// 立即清理到期条目。
  Future<void> _onCleanup() async {
    final int cleaned = await _controller.cleanupDue();
    if (!mounted) return;
    VboxToast.show(
      context,
      cleaned > 0 ? '已清理 $cleaned 项' : '暂无可清理项（未到期）',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBack,
        ),
        title: Text('${widget.driveType.displayName} 文件列表'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.load(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? _) {
          return ListView(
            padding: const EdgeInsets.all(VboxSpacing.lg),
            children: <Widget>[
              _breadcrumb(scheme),
              const SizedBox(height: VboxSpacing.md),
              _entrySection(scheme),
              const SizedBox(height: VboxSpacing.lg),
              _cleanupCard(scheme),
            ],
          );
        },
      ),
    );
  }

  /// 面包屑（网盘 logo + 路径）。
  Widget _breadcrumb(ColorScheme scheme) {
    return Row(
      children: <Widget>[
        VboxDriveLogo(type: widget.driveType, size: 24),
        const SizedBox(width: VboxSpacing.sm),
        Expanded(
          child: Text(
            _controller.breadcrumb,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: VboxTypography.s13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _entrySection(ColorScheme scheme) {
    if (_controller.loading && _controller.entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(VboxSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final String? error = _controller.error;
    if (error != null) {
      return _placeholder(scheme, error, Icons.error_outline, scheme.error);
    }
    if (_controller.entries.isEmpty) {
      return _placeholder(
        scheme,
        '当前目录没有文件',
        Icons.folder_open,
        scheme.onSurfaceVariant,
      );
    }
    return Column(
      children: <Widget>[
        for (final CloudDriveFileEntry entry in _controller.entries)
          _entryRow(scheme, entry),
      ],
    );
  }

  /// 文件 / 文件夹行。
  Widget _entryRow(ColorScheme scheme, CloudDriveFileEntry entry) {
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(VboxRadii.r10),
      child: InkWell(
        key: ValueKey<String>('cloud_file_${entry.fileId}'),
        borderRadius: BorderRadius.circular(VboxRadii.r10),
        onTap: entry.isFolder
            ? () => _controller.openFolder(entry)
            : () => _onTransfer(entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VboxSpacing.md,
            vertical: 12,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                entry.isFolder ? Icons.folder : _fileIcon(entry),
                size: VboxTypography.s18,
                color: entry.isFolder
                    ? VboxColors.warning
                    : cloudDriveBrandColor(widget.driveType),
              ),
              const SizedBox(width: VboxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: VboxTypography.s14,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (!entry.isFolder) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        formatFileSize(entry.size),
                        style: TextStyle(
                          fontSize: VboxTypography.s11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                entry.isFolder ? Icons.chevron_right : Icons.save_alt,
                size: VboxTypography.s16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(
    ColorScheme scheme,
    String text,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: VboxSpacing.xxl),
      alignment: Alignment.center,
      child: Column(
        children: <Widget>[
          Icon(icon, size: 40, color: color.withValues(alpha: 0.6)),
          const SizedBox(height: VboxSpacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: VboxTypography.s13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 清理队列卡（对齐 iOS `scheduleCleanup` 的待清理计数面）。
  Widget _cleanupCard(ColorScheme scheme) {
    final int count = _controller.queueCount;
    final bool enabled = count > 0;
    return Container(
      padding: const EdgeInsets.all(VboxSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(VboxRadii.r12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.cleaning_services_outlined,
            size: VboxTypography.s18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: VboxSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '清理队列',
                  style: TextStyle(
                    fontSize: VboxTypography.s14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count > 0 ? '待清理 $count 项' : '暂无待清理项',
                  style: TextStyle(
                    fontSize: VboxTypography.s12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: enabled
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(VboxRadii.r8),
            child: InkWell(
              key: const ValueKey<String>('cloud_cleanup_now'),
              onTap: enabled ? _onCleanup : null,
              borderRadius: BorderRadius.circular(VboxRadii.r8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VboxSpacing.md,
                  vertical: 8,
                ),
                child: Text(
                  '立即清理',
                  style: TextStyle(
                    fontSize: VboxTypography.s13,
                    fontWeight: FontWeight.w500,
                    color:
                        enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _fileIcon(CloudDriveFileEntry entry) =>
    entry.isVideo ? Icons.movie_outlined : Icons.insert_drive_file_outlined;

/// 文件大小格式化（B / KB / MB / GB，对齐 iOS 列表口径）。
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
