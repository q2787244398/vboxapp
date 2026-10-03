/// 网盘文件列表控制器（批次 F · F-07）。
///
/// 对齐 iOS 播放链「多文件列表 + 转存 + 清理队列」面：
/// - 目录列举经 [CloudDriveFileLister]（缺省「未接入」直报错，与 iOS A1 接缝
///   未就绪行为一致）；
/// - 转存后按 `pg_ali_cleanup_delay`（默认 180s）入队清理
///   （对齐 iOS `scheduleCleanup(fileIds:token:delay:)`）；
/// - 清理队列持久化契约键 `cloud_drive_cleanup_queue_v1`
///   （[CloudDriveCleanupQueueStore]）。
library;

import 'package:flutter/foundation.dart';

import '../../../data/datasources/local/cloud_drive_cleanup_queue_store.dart';
import '../../../data/datasources/local/prefs_manager.dart';
import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/cloud_drive_files.dart';

/// 目录列举接缝（真实实现走 Node 常驻系统 / 网盘 OpenAPI）。
abstract interface class CloudDriveFileLister {
  /// 列举 [parentId] 下的条目（根目录传空串）。
  Future<List<CloudDriveFileEntry>> list({
    required CloudDriveType drive,
    required String parentId,
  });
}

/// 未接入列举器：直接报错（对齐 iOS 缺省「Node 常驻系统未就绪」口径）。
class UnavailableCloudDriveFileLister implements CloudDriveFileLister {
  /// 构造。
  const UnavailableCloudDriveFileLister();

  @override
  Future<List<CloudDriveFileEntry>> list({
    required CloudDriveType drive,
    required String parentId,
  }) async =>
      throw const CloudDriveFilesException('网盘文件链路尚未接入（等待 Node 常驻系统就绪）');
}

/// 文件列表异常。
class CloudDriveFilesException implements Exception {
  /// 构造。
  const CloudDriveFilesException(this.message);

  /// 文案。
  final String message;

  @override
  String toString() => message;
}

/// 文件列表控制器。
class CloudDriveFilesController extends ChangeNotifier {
  /// 构造。
  CloudDriveFilesController({
    required this.driveType,
    CloudDriveFileLister? lister,
    CloudDriveCleanupQueueStore? cleanupStore,
    Duration cleanupDelay = const Duration(seconds: 180),
  })  : _lister = lister ?? const UnavailableCloudDriveFileLister(),
        _cleanupStore =
            cleanupStore ?? CloudDriveCleanupQueueStore(PrefsManager.instance),
        _cleanupDelay = cleanupDelay;

  /// 目标网盘。
  final CloudDriveType driveType;

  final CloudDriveFileLister _lister;
  final CloudDriveCleanupQueueStore _cleanupStore;
  final Duration _cleanupDelay;

  /// 当前目录 ID（根为空串）。
  String _parentId = '';

  /// 当前路径（面包屑，根为网盘名）。
  final List<(String, String)> _path = <(String, String)>[];

  List<CloudDriveFileEntry> _entries = <CloudDriveFileEntry>[];
  int _queueCount = 0;
  bool _loading = false;
  String? _error;

  /// 当前目录条目（文件夹优先排序）。
  List<CloudDriveFileEntry> get entries => _entries;

  /// 清理队列条目数。
  int get queueCount => _queueCount;

  /// 是否加载中。
  bool get loading => _loading;

  /// 错误文案（null 表示无错误）。
  String? get error => _error;

  /// 当前路径 ID。
  String get parentId => _parentId;

  /// 面包屑文本（根 = 网盘显示名）。
  String get breadcrumb {
    if (_path.isEmpty) return driveType.displayName;
    return '${driveType.displayName} / '
        '${_path.map(((String, String) e) => e.$2).join(' / ')}';
  }

  /// 加载当前目录 + 刷新队列计数。
  Future<void> load({String? parentId}) async {
    if (parentId != null) _parentId = parentId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final List<CloudDriveFileEntry> list = await _lister.list(
        drive: driveType,
        parentId: _parentId,
      );
      list.sort(
        (CloudDriveFileEntry a, CloudDriveFileEntry b) => a.compareTo(b),
      );
      _entries = list;
    } catch (e) {
      _entries = <CloudDriveFileEntry>[];
      _error = e is CloudDriveFilesException ? e.message : '$e';
    }
    _queueCount = await _cleanupStore.count();
    _loading = false;
    notifyListeners();
  }

  /// 进入子目录。
  Future<void> openFolder(CloudDriveFileEntry folder) async {
    if (!folder.isFolder) return;
    _path.add((folder.fileId, folder.name));
    await load(parentId: folder.fileId);
  }

  /// 返回上级目录（根目录时无操作，返回 false）。
  Future<bool> goUp() async {
    if (_path.isEmpty) return false;
    _path.removeLast();
    await load(parentId: _path.isEmpty ? '' : _path.last.$1);
    return true;
  }

  /// 转存条目并把产生的文件 ID 入清理队列（去重）。
  ///
  /// 返回本次真正新增的队列条目数（0 表示全部命中已有去重键）。
  Future<int> transferAndSchedule(
    Iterable<String> fileIds, {
    String tokenName = '',
    DateTime? now,
  }) async {
    final DateTime stamp = now ?? DateTime.now();
    final List<CloudDriveCleanupItem> before = await _cleanupStore.load();
    final List<CloudDriveCleanupItem> after = await _cleanupStore.enqueue(
      drive: driveType.id,
      tokenName: tokenName,
      fileIds: fileIds,
      delay: _cleanupDelay,
      now: stamp,
    );
    _queueCount = after.length;
    notifyListeners();
    return after.length - before.length;
  }

  /// 立即执行到期清理（提交删除后移除到期条目），返回清理条数。
  Future<int> cleanupDue({DateTime? now}) async {
    final List<CloudDriveCleanupItem> expired =
        await _cleanupStore.due(now: now);
    if (expired.isEmpty) return 0;
    await _cleanupStore.removeDue(now: now);
    _queueCount = await _cleanupStore.count();
    notifyListeners();
    return expired.length;
  }
}
