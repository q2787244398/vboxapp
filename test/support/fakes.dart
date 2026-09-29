/// 测试替身：内存仓储实现（供用例层单测注入）。
library;

import 'package:vbox/core/errors/failures.dart';
import 'package:vbox/core/utils/result.dart';
import 'package:vbox/domain/entities/library/library.dart';
import 'package:vbox/domain/entities/remote_source/remote_source.dart';
import 'package:vbox/domain/repositories/repositories.dart';

/// 内存收藏仓储。
class InMemoryFavoriteRepository implements FavoriteRepository {
  /// 构造（可注入初值）。
  InMemoryFavoriteRepository([List<FavoriteItem>? seed])
      : _items = <FavoriteItem>[...?seed];

  final List<FavoriteItem> _items;
  int _seq = 1000;

  /// 非空时所有操作返回该失败（模拟故障）。
  Failure? failWith;

  /// 当前条目数（测试断言用）。
  int get length => _items.length;

  @override
  Future<Result<List<FavoriteItem>>> list({int? limit, int? offset}) async {
    final Failure? f = failWith;
    if (f != null) return Err<List<FavoriteItem>>(f);
    final List<FavoriteItem> sorted = <FavoriteItem>[..._items]
      ..sort((FavoriteItem a, FavoriteItem b) =>
          b.addedAt.compareTo(a.addedAt));
    final int start = offset ?? 0;
    if (start >= sorted.length) {
      return const Success<List<FavoriteItem>>(<FavoriteItem>[]);
    }
    final List<FavoriteItem> sliced = sorted.sublist(start);
    if (limit == null || limit >= sliced.length) {
      return Success<List<FavoriteItem>>(sliced);
    }
    return Success<List<FavoriteItem>>(sliced.sublist(0, limit));
  }

  @override
  Future<Result<FavoriteItem?>> findByDetailUrl(String detailurl) async {
    final Failure? f = failWith;
    if (f != null) return Err<FavoriteItem?>(f);
    for (final FavoriteItem item in _items) {
      if (item.detailurl == detailurl) return Success<FavoriteItem?>(item);
    }
    return const Success<FavoriteItem?>(null);
  }

  @override
  Future<Result<FavoriteItem?>> findById(int id) async {
    final Failure? f = failWith;
    if (f != null) return Err<FavoriteItem?>(f);
    for (final FavoriteItem item in _items) {
      if (item.id == id) return Success<FavoriteItem?>(item);
    }
    return const Success<FavoriteItem?>(null);
  }

  @override
  Future<Result<int>> add(FavoriteItem item) async {
    final Failure? f = failWith;
    if (f != null) return Err<int>(f);
    final int id = _seq++;
    _items.add(item.copyWith(id: id));
    return Success<int>(id);
  }

  @override
  Future<Result<bool>> remove(int id) async {
    final Failure? f = failWith;
    if (f != null) return Err<bool>(f);
    final int before = _items.length;
    _items.removeWhere((FavoriteItem item) => item.id == id);
    return Success<bool>(_items.length != before);
  }

  @override
  Future<Result<int>> clear() async {
    final Failure? f = failWith;
    if (f != null) return Err<int>(f);
    final int n = _items.length;
    _items.clear();
    return Success<int>(n);
  }

  @override
  Future<Result<int>> count() async => Success<int>(_items.length);
}

/// 内存历史仓储。
class InMemoryHistoryRepository implements HistoryRepository {
  /// 构造。
  InMemoryHistoryRepository([List<HistoryItem>? seed])
      : _items = <HistoryItem>[...?seed];

  final List<HistoryItem> _items;
  int _seq = 2000;

  /// 模拟故障。
  Failure? failWith;

  /// 当前条目数。
  int get length => _items.length;

  /// 最近一次 upsert 的入参（断言进度钳制用）。
  HistoryItem? lastUpsert;

  @override
  Future<Result<List<HistoryItem>>> list({int? limit}) async {
    final Failure? f = failWith;
    if (f != null) return Err<List<HistoryItem>>(f);
    final List<HistoryItem> sorted = <HistoryItem>[..._items]
      ..sort((HistoryItem a, HistoryItem b) =>
          b.lastPlayedAt.compareTo(a.lastPlayedAt));
    if (limit == null || limit >= sorted.length) {
      return Success<List<HistoryItem>>(sorted);
    }
    return Success<List<HistoryItem>>(sorted.sublist(0, limit));
  }

  @override
  Future<Result<HistoryItem?>> findByDetailUrl(String detailurl) async {
    final Failure? f = failWith;
    if (f != null) return Err<HistoryItem?>(f);
    for (final HistoryItem item in _items) {
      if (item.detailurl == detailurl) return Success<HistoryItem?>(item);
    }
    return const Success<HistoryItem?>(null);
  }

  @override
  Future<Result<int>> upsert(HistoryItem item) async {
    final Failure? f = failWith;
    if (f != null) return Err<int>(f);
    lastUpsert = item;
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].detailurl == item.detailurl) {
        final int id = _items[i].id ?? _seq++;
        _items[i] = item.copyWith(id: id);
        return Success<int>(id);
      }
    }
    final int id = _seq++;
    _items.add(item.copyWith(id: id));
    return Success<int>(id);
  }

  @override
  Future<Result<bool>> remove(int id) async {
    final Failure? f = failWith;
    if (f != null) return Err<bool>(f);
    final int before = _items.length;
    _items.removeWhere((HistoryItem item) => item.id == id);
    return Success<bool>(_items.length != before);
  }

  @override
  Future<Result<int>> clear() async {
    final int n = _items.length;
    _items.clear();
    return Success<int>(n);
  }

  @override
  Future<Result<int>> trim(int keep) async {
    final Failure? f = failWith;
    if (f != null) return Err<int>(f);
    final List<HistoryItem> sorted = <HistoryItem>[..._items]
      ..sort((HistoryItem a, HistoryItem b) =>
          b.lastPlayedAt.compareTo(a.lastPlayedAt));
    final List<HistoryItem> drop = sorted.skip(keep).toList();
    _items.removeWhere((HistoryItem item) => drop.contains(item));
    return Success<int>(drop.length);
  }

  @override
  Future<Result<int>> count() async => Success<int>(_items.length);
}

/// 内存订阅仓储。
class InMemorySubscriptionRepository implements SubscriptionRepository {
  /// 构造。
  InMemorySubscriptionRepository([List<SubscriptionItem>? seed])
      : _items = <SubscriptionItem>[...?seed];

  final List<SubscriptionItem> _items;
  int _seq = 3000;

  /// 模拟故障。
  Failure? failWith;

  @override
  Future<Result<List<SubscriptionItem>>> list() async {
    final Failure? f = failWith;
    if (f != null) return Err<List<SubscriptionItem>>(f);
    return Success<List<SubscriptionItem>>(<SubscriptionItem>[..._items]);
  }

  @override
  Future<Result<SubscriptionItem?>> findByUrl(String dyurl) async {
    final Failure? f = failWith;
    if (f != null) return Err<SubscriptionItem?>(f);
    for (final SubscriptionItem item in _items) {
      if (item.dyurl == dyurl) {
        return Success<SubscriptionItem?>(item);
      }
    }
    return const Success<SubscriptionItem?>(null);
  }

  @override
  Future<Result<SubscriptionItem?>> findById(int id) async {
    for (final SubscriptionItem item in _items) {
      if (item.id == id) return Success<SubscriptionItem?>(item);
    }
    return const Success<SubscriptionItem?>(null);
  }

  @override
  Future<Result<int>> add(SubscriptionItem item) async {
    final Failure? f = failWith;
    if (f != null) return Err<int>(f);
    final int id = _seq++;
    _items.add(item.copyWith(id: id));
    return Success<int>(id);
  }

  @override
  Future<Result<bool>> remove(int id) async {
    final Failure? f = failWith;
    if (f != null) return Err<bool>(f);
    final int before = _items.length;
    _items.removeWhere((SubscriptionItem item) => item.id == id);
    return Success<bool>(_items.length != before);
  }

  @override
  Future<Result<bool>> touchSync(int id, int atSeconds) async {
    final Failure? f = failWith;
    if (f != null) return Err<bool>(f);
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].id == id) {
        _items[i] = _items[i].copyWith(lastSyncAt: atSeconds);
        return const Success<bool>(true);
      }
    }
    return const Success<bool>(false);
  }
}

/// 内存远程源仓储。
class InMemoryRemoteSourceRepository implements RemoteSourceRepository {
  /// 缓存清单（可注入）。
  RemoteManifest? cached;

  /// 缓存写入时间（Unix 秒）。
  int cachedAt = 0;

  /// saveManifest 时写入的时间戳（测试注入）。
  int cachedAtHint = 0;

  /// fetch 返回的清单。
  RemoteManifest? fetchResult;

  /// fetch 返回的失败（非空则优先）。
  Failure? fetchFailure;

  /// fetch 调用次数（断言 TTL 命中不再拉取）。
  int fetchCount = 0;

  /// saveManifest 调用次数。
  int saveCount = 0;

  @override
  Future<Result<RemoteManifest>> fetchManifest({bool forceRefresh = false}) async {
    fetchCount++;
    final Failure? f = fetchFailure;
    if (f != null) return Err<RemoteManifest>(f);
    final RemoteManifest? m = fetchResult;
    if (m == null) {
      return const Err<RemoteManifest>(UnknownFailure('fake 未设置 fetchResult'));
    }
    return Success<RemoteManifest>(m);
  }

  @override
  Future<Result<RemoteManifest?>> cachedManifest() async =>
      Success<RemoteManifest?>(cached);

  @override
  Future<Result<bool>> saveManifest(RemoteManifest manifest) async {
    saveCount++;
    cached = manifest;
    // 写入时间由测试显式设置（fake 不掌握真实时钟）
    cachedAt = cachedAtHint;
    return const Success<bool>(true);
  }

  @override
  Future<Result<bool>> needsRefresh(int nowSeconds) async {
    final RemoteManifest? c = cached;
    if (c == null) return const Success<bool>(true);
    return Success<bool>(nowSeconds - cachedAt >= c.ttlSeconds);
  }

  @override
  Future<Result<int>> cachedAtSeconds() async => Success<int>(cachedAt);
}

/// 构造测试用清单。
RemoteManifest buildManifest({
  String configVersion = '2026.09.29.1',
  int ttlSeconds = 3600,
  bool withRequiredFiles = true,
  Map<String, Object?>? meta,
}) =>
    RemoteManifest.fromJson(<String, Object?>{
      'schemaVersion': 1,
      'configVersion': configVersion,
      'ttlSeconds': ttlSeconds,
      'forceRefresh': false,
      'disabledKeys': <String>[],
      'files': withRequiredFiles
          ? <String, String>{
              'allSources': 'https://cdn.example.com/all_sources.json',
            }
          : <String, String>{
              'parsers': 'https://cdn.example.com/parsers.json',
            },
      if (meta != null) '_meta': meta,
    });
