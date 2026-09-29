/// 核心层单测：日志（环形缓冲 + 过滤导出 + 广播流）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/core/constants/app_constants.dart';
import 'package:vbox/core/utils/logger.dart';

void main() {
  setUp(AppLog.clear);
  tearDown(AppLog.clear);

  test('基础写入与级别', () {
    AppLog.info('T', 'hello');
    AppLog.error('T', 'boom', error: StateError('e'));
    expect(AppLog.length, 2);
    expect(AppLog.entries.first.level, LogLevel.info);
    expect(AppLog.entries.last.message, 'boom');
    expect(AppLog.entries.last.error, isA<StateError>());
  });

  test('format 含级别与标签', () {
    AppLog.warn('DbMgr', '慢查询');
    final String line = AppLog.entries.single.format();
    expect(line.contains('WARN'), isTrue);
    expect(line.contains('DbMgr: 慢查询'), isTrue);
    // 时间戳格式 yyyy-MM-dd HH:mm:ss
    expect(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} ').hasMatch(line), isTrue);
  });

  test('环形缓冲按容量淘汰最旧', () {
    final int cap = LogConstants.ringBufferSize;
    for (int i = 0; i < cap + 5; i++) {
      AppLog.debug('T', 'line$i');
    }
    expect(AppLog.length, cap);
    expect(AppLog.entries.first.message, 'line5');
    expect(AppLog.entries.last.message, 'line${cap + 4}');
  });

  test('dump 支持级别过滤与条数限制', () {
    AppLog.debug('T', 'd1');
    AppLog.info('T', 'i1');
    AppLog.warn('T', 'w1');
    AppLog.error('T', 'e1');

    expect(AppLog.dump().split('\n').length, 4);

    final String warnOnly = AppLog.dump(minLevel: LogLevel.warn);
    expect(warnOnly.contains('w1'), isTrue);
    expect(warnOnly.contains('e1'), isTrue);
    expect(warnOnly.contains('i1'), isFalse);

    final List<String> lastTwo = AppLog.dump(limit: 2).split('\n');
    expect(lastTwo.length, 2);
    expect(lastTwo.first.contains('w1'), isTrue);
  });

  test('广播流可订阅', () async {
    final Future<LogEntry> first = AppLog.stream.first;
    AppLog.info('T', 'streamed');
    final LogEntry e = await first;
    expect(e.message, 'streamed');
  });

  test('clear 后缓冲为空', () {
    AppLog.info('T', 'x');
    AppLog.clear();
    expect(AppLog.length, 0);
    expect(AppLog.dump(), '');
  });
}
