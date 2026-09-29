/// 核心层：日志。
///
/// 设计对齐 iOS `vbox/Services/AppLogStore.swift`：
/// - 内存环形缓冲（容量见 `LogConstants.ringBufferSize`），供「日志查看」页面读取；
/// - 广播流，供实时订阅（调试面板）；
/// - **不落盘**：落盘由平台层/数据层负责，核心层保持纯 Dart、可单测。
library;

import 'dart:async';

import '../constants/app_constants.dart';

/// 日志级别。
enum LogLevel {
  /// 调试。
  debug,

  /// 常规信息。
  info,

  /// 警告。
  warn,

  /// 错误。
  error,
}

/// 单条日志。
class LogEntry {
  /// 构造。
  const LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
  });

  /// 发生时间。
  final DateTime time;

  /// 级别。
  final LogLevel level;

  /// 标签（一般传类名/模块名）。
  final String tag;

  /// 正文。
  final String message;

  /// 关联错误（可空）。
  final Object? error;

  /// 单行格式化。
  String format() {
    final StringBuffer sb = StringBuffer()
      ..write(_timestamp(time))
      ..write(' [')
      ..write(level.name.toUpperCase().padRight(5))
      ..write('] ')
      ..write(tag)
      ..write(': ')
      ..write(message);
    if (error != null) {
      sb.write(' ← ');
      sb.write(error);
    }
    return sb.toString();
  }

  @override
  String toString() => format();

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// 全局日志器（无第三方依赖，可单测）。
abstract final class AppLog {
  static final List<LogEntry> _entries = <LogEntry>[];
  static final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  /// 当前缓冲条数。
  static int get length => _entries.length;

  /// 缓冲快照（只读）。
  static List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  /// 实时订阅。
  static Stream<LogEntry> get stream => _controller.stream;

  /// 写入一条日志。
  static void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
  }) {
    final LogEntry entry = LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
    );
    _entries.add(entry);
    final int overflow = _entries.length - LogConstants.ringBufferSize;
    if (overflow > 0) {
      _entries.removeRange(0, overflow);
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  /// debug 级。
  static void debug(String tag, String message, {Object? error}) =>
      log(LogLevel.debug, tag, message, error: error);

  /// info 级。
  static void info(String tag, String message, {Object? error}) =>
      log(LogLevel.info, tag, message, error: error);

  /// warn 级。
  static void warn(String tag, String message, {Object? error}) =>
      log(LogLevel.warn, tag, message, error: error);

  /// error 级。
  static void error(String tag, String message, {Object? error}) =>
      log(LogLevel.error, tag, message, error: error);

  /// 清空缓冲（不影响订阅者）。
  static void clear() => _entries.clear();

  /// 导出文本（`limit` 为最大条数，取**最新**若干条）。
  static String dump({LogLevel? minLevel, int? limit}) {
    Iterable<LogEntry> list = _entries;
    if (minLevel != null) {
      list = list.where((LogEntry e) => e.level.index >= minLevel.index);
    }
    if (limit != null && list.length > limit) {
      list = list.skip(list.length - limit);
    }
    return list.map((LogEntry e) => e.format()).join('\n');
  }
}
