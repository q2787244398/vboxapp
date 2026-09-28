import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Local persistence via sqflite (reconstructed without codegen Isar).
///
/// Stores search history, watch history, and simple key/value settings.
/// (The original build used Isar's embedded engine; sqflite is API-
/// equivalent for these small datasets and keeps the source portable.)
class DatabaseService with ChangeNotifier {
  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/tvs.db';
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE search_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            keyword TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 1,
            timestamp INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE watch_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vod_id TEXT NOT NULL,
            vod_name TEXT NOT NULL,
            site_key TEXT,
            position_ms INTEGER NOT NULL DEFAULT 0,
            timestamp INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE kv (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
  }

  // ----- search history -----

  Future<SearchHistory> addSearchHistory(String keyword) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'search_history',
      where: 'keyword = ?',
      whereArgs: [keyword],
    );
    if (rows.isNotEmpty) {
      final row = rows.first;
      await db.update(
        'search_history',
        {'count': (row['count'] as int) + 1, 'timestamp': now},
        where: 'keyword = ?',
        whereArgs: [keyword],
      );
      return SearchHistory(
        id: row['id'] as int,
        keyword: keyword,
        count: (row['count'] as int) + 1,
        timestamp: now,
      );
    }
    final id = await db.insert('search_history',
        {'keyword': keyword, 'count': 1, 'timestamp': now});
    return SearchHistory(id: id, keyword: keyword, count: 1, timestamp: now);
  }

  Future<List<SearchHistory>> getSearchHistory({
    int limit = 50,
    SearchHistorySort sort = SearchHistorySort.recent,
  }) async {
    final db = await database;
    final orderBy =
        sort == SearchHistorySort.recent ? 'timestamp DESC' : 'count DESC';
    final rows = await db.query('search_history', orderBy: orderBy, limit: limit);
    return rows
        .map((r) => SearchHistory(
            id: r['id'] as int,
            keyword: r['keyword'] as String,
            count: r['count'] as int,
            timestamp: r['timestamp'] as int))
        .toList();
  }

  Future<void> deleteSearchHistoryEntry(int id) async {
    final db = await database;
    await db.delete('search_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearSearchHistory() async {
    final db = await database;
    await db.delete('search_history');
    notifyListeners();
  }

  // ----- watch history -----

  Future<void> addWatchHistory(
    Vod vod, {
    int positionMs = 0,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('watch_history', {
      'vod_id': vod.id,
      'vod_name': vod.name,
      'site_key': vod.siteKey,
      'position_ms': positionMs,
      'timestamp': now,
    });
  }

  Future<List<WatchHistory>> getWatchHistory({int limit = 100}) async {
    final db = await database;
    final rows =
        await db.query('watch_history', orderBy: 'timestamp DESC', limit: limit);
    return rows
        .map((r) => WatchHistory(
            id: r['id'] as int,
            vodId: r['vod_id'] as String,
            vodName: r['vod_name'] as String,
            siteKey: r['site_key'] as String?,
            positionMs: r['position_ms'] as int,
            timestamp: r['timestamp'] as int))
        .toList();
  }

  Future<void> clearWatchHistory() async {
    final db = await database;
    await db.delete('watch_history');
    notifyListeners();
  }

  // ----- key/value -----

  Future<void> putKv(String key, dynamic value) async {
    final db = await database;
    await db.insert(
      'kv',
      {'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<T?> getKv<T>(String key) async {
    final db = await database;
    final rows =
        await db.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final raw = rows.first['value'] as String?;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
