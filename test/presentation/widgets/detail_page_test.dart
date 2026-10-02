/// 表现层 widget 测试：详情页（加载 / 失败重试 / 线路与剧集 / 播放入口）。
///
/// 注入假 [DetailPlaybackUseCases]（子类覆盖 loadDetail / resolvePlayUrl）；
/// 播放链路注入 `PlayerController.overrideForTest` 假控制器；无 IO、无原生依赖。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/errors/failures.dart';
import 'package:vbox/core/utils/result.dart';
import 'package:vbox/domain/entities/player/player.dart';
import 'package:vbox/domain/entities/playback/playback.dart';
import 'package:vbox/domain/entities/remote_source/remote_source.dart';
import 'package:vbox/domain/entities/spider/spider.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/platform/player/playback_route.dart';
import 'package:vbox/platform/player/player_channel_bridge.dart';
import 'package:vbox/platform/player/player_controller.dart';
import 'package:vbox/presentation/widgets/detail_page.dart';

// ─────────────── 测试替身 ───────────────

/// 假用例：覆盖详情加载与播放地址解析。
class _FakeDetailUseCases extends DetailPlaybackUseCases {
  _FakeDetailUseCases({this.detailResult, this.playerResult})
      : super(
          loadAllSources: () async =>
              const Success<AllSourcesContainer>(AllSourcesContainer()),
        );

  Future<Result<PlaybackDetail>> Function()? detailResult;
  Future<Result<PlayerContentResult>> Function()? playerResult;
  int loadCalls = 0;

  @override
  Future<Result<PlaybackDetail>> loadDetail({
    required String siteKey,
    required String vodId,
    int initialIndex = 0,
  }) {
    loadCalls++;
    final Future<Result<PlaybackDetail>> Function()? f = detailResult;
    if (f == null) {
      return Future<Result<PlaybackDetail>>.value(
        const Err<PlaybackDetail>(UnknownFailure('未注入 detailResult')),
      );
    }
    return f();
  }

  @override
  Future<Result<PlayerContentResult>> resolvePlayUrl({
    required PlaybackDetail detail,
    required PlaybackEpisode episode,
  }) {
    final Future<Result<PlayerContentResult>> Function()? f = playerResult;
    if (f == null) {
      return Future<Result<PlayerContentResult>>.value(
        Success<PlayerContentResult>(PlayerContentResult(url: episode.url)),
      );
    }
    return f();
  }
}

/// 假播放器控制器：记录 open/play 调用。
class _FakePlayerController extends PlayerController {
  _FakePlayerController()
      : super(
          bridge: _NoopBridge(),
          backendChain: const <PlayerBackend>[PlayerBackend.media3],
          selectInitialBackend: (_, PlaybackRoute route) => PlayerBackend.media3,
        );

  final List<String> calls = <String>[];
  String? openedUrl;

  @override
  Future<void> open(PlayerSource source) async {
    calls.add('open');
    openedUrl = source.url;
  }

  @override
  Future<void> play() async => calls.add('play');
}

class _NoopBridge implements PlayerChannelBridge {
  @override
  Future<Object?> invoke(String method, [Object? arguments]) async => null;

  @override
  Stream<Map<String, Object?>> events() =>
      const Stream<Map<String, Object?>>.empty();

  @override
  Future<void> dispose() async {}
}

// ─────────────── 数据构造 ───────────────

VodItem vod({String? playUrl}) => VodItem.fromJson(<String, Object?>{
      'vod_id': '123',
      'vod_name': '示例片',
      'vod_pic': '',
      'vod_play_from': '线路1\$\$\$线路2',
      'vod_play_url': playUrl ??
          '第1集\$https://v.com/1.m3u8#第2集\$https://v.com/2.m3u8'
              '\$\$\$第1集\$https://v.com/3.m3u8',
    });

PlaybackDetail detail({String? playUrl, int initialIndex = 0}) =>
    PlaybackDetail.fromVod(
      site: SiteConfig.fromJson(<String, Object?>{
        'key': 's1',
        'name': '站点1',
        'type': 0,
      }),
      vod: vod(playUrl: playUrl),
      initialIndex: initialIndex,
    );

Widget _app(_FakeDetailUseCases uc, {int initialIndex = 0}) => MultiProvider(
      providers: [
        Provider<DetailPlaybackUseCases>.value(value: uc),
      ],
      child: MaterialApp(
        home: DetailPage(
          siteKey: 's1',
          vodId: '123',
          initialIndex: initialIndex,
          title: '详情',
        ),
      ),
    );

void main() {
  late _FakePlayerController player;

  setUp(() {
    player = _FakePlayerController();
    PlayerController.overrideForTest(player);
  });

  testWidgets('加载中：显示进度圈，完成后展示详情', (WidgetTester tester) async {
    final Completer<Result<PlaybackDetail>> completer =
        Completer<Result<PlaybackDetail>>();
    final _FakeDetailUseCases uc =
        _FakeDetailUseCases(detailResult: () => completer.future);
    await tester.pumpWidget(_app(uc));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(Success<PlaybackDetail>(detail()));
    await tester.pumpAndSettle();
    expect(find.text('示例片'), findsOneWidget);
  });

  testWidgets('加载失败：错误提示 + 重试后恢复', (WidgetTester tester) async {
    final _FakeDetailUseCases uc = _FakeDetailUseCases(
      detailResult: () async =>
          const Err<PlaybackDetail>(NetworkFailure('断网')),
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    expect(find.textContaining('断网'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    uc.detailResult = () async => Success<PlaybackDetail>(detail());
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(uc.loadCalls, 2);
    expect(find.text('示例片'), findsOneWidget);
  });

  testWidgets('加载成功：影片信息 / 线路 / 剧集 / 播放按钮', (WidgetTester tester) async {
    final _FakeDetailUseCases uc = _FakeDetailUseCases(
      detailResult: () async => Success<PlaybackDetail>(detail()),
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    expect(find.text('示例片'), findsOneWidget);
    expect(find.text('线路1'), findsOneWidget);
    expect(find.text('线路2'), findsOneWidget);
    expect(find.text('第1集'), findsOneWidget);
    expect(find.text('第2集'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
  });

  testWidgets('线路切换：仅显示该线路剧集', (WidgetTester tester) async {
    final _FakeDetailUseCases uc = _FakeDetailUseCases(
      detailResult: () async => Success<PlaybackDetail>(detail()),
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    // 初始线路1：第1集 + 第2集
    expect(find.text('第1集'), findsOneWidget);
    expect(find.text('第2集'), findsOneWidget);

    await tester.tap(find.text('线路2'));
    await tester.pumpAndSettle();

    expect(find.text('第2集'), findsNothing);
    expect(find.text('第1集'), findsOneWidget);
  });

  testWidgets('续播入口：initialIndex 指向的剧集高亮', (WidgetTester tester) async {
    final _FakeDetailUseCases uc = _FakeDetailUseCases(
      detailResult: () async =>
          Success<PlaybackDetail>(detail(initialIndex: 1)),
    );
    await tester.pumpWidget(_app(uc, initialIndex: 1));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(ActionChip, '第2集'),
        matching: find.byIcon(Icons.play_arrow),
      ),
      findsOneWidget,
    );
  });

  testWidgets('点击播放：resolvePlayUrl → PlayerController.open/play', (WidgetTester tester) async {
    final _FakeDetailUseCases uc = _FakeDetailUseCases(
      detailResult: () async => Success<PlaybackDetail>(detail()),
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(player.calls, <String>['open', 'play']);
    expect(player.openedUrl, 'https://v.com/1.m3u8');
    expect(find.textContaining('开始播放：第1集'), findsOneWidget);
  });

  testWidgets('解析失败：SnackBar 提示', (WidgetTester tester) async {
    final _FakeDetailUseCases uc = _FakeDetailUseCases(
      detailResult: () async => Success<PlaybackDetail>(detail()),
      playerResult: () async =>
          const Err<PlayerContentResult>(ParseFailure('无法解析')),
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(player.calls, isEmpty);
    expect(find.textContaining('解析失败'), findsOneWidget);
  });

  testWidgets('无剧集：播放按钮禁用', (WidgetTester tester) async {
    final _FakeDetailUseCases uc = _FakeDetailUseCases(
      detailResult: () async => Success<PlaybackDetail>(detail(playUrl: '')),
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    expect(find.text('暂无剧集'), findsOneWidget);
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();
    expect(player.calls, isEmpty);
  });
}
