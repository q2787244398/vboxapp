/// 网盘播放（pan 模式）编排单测（批次 F · F-08）。
///
/// 覆盖：路由通道判定 / Node 托管盘解析 / 缓存落盘 / 显式 pan 路由打开 / 汇总与失效。
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/data/datasources/local/cloud_play_item_cache_store.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/data/datasources/remote/baidu_proxy_client.dart';
import 'package:vbox/data/datasources/remote/node_pan_client.dart';
import 'package:vbox/data/datasources/remote/quark_native_client.dart';
import 'package:vbox/domain/entities/cloud/baidu_proxy.dart';
import 'package:vbox/domain/entities/cloud/cloud_drive.dart';
import 'package:vbox/domain/entities/cloud/cloud_play_item.dart';
import 'package:vbox/domain/entities/cloud/node_pan.dart';
import 'package:vbox/domain/entities/player/player.dart';
import 'package:vbox/platform/player/pan_player.dart';
import 'package:vbox/platform/player/playback_route.dart';
import 'package:vbox/platform/player/player_channel_bridge.dart';
import 'package:vbox/platform/player/player_controller.dart';

String _idWithName(String name) =>
    base64.encode(utf8.encode(jsonEncode(<String, String>{'name': name})));

class _FakeTransport implements NodePanTransport {
  _FakeTransport(this.handler);

  final Future<NodePanHttpResponse> Function(String, Map<String, dynamic>)
      handler;

  @override
  Future<NodePanHttpResponse> postJson(
    String path,
    Map<String, dynamic> body,
  ) =>
      handler(path, body);
}

/// 成功返回 detail + play 的传输替身。
NodePanTransport _happyTransport() => _FakeTransport((String path, _) async {
      if (path == NodePanPaths.detail) {
        return NodePanHttpResponse(
          statusCode: 200,
          json: <String, dynamic>{
            'list': <Map<String, dynamic>>[
              <String, dynamic>{
                'vod_name': '示例剧',
                'vod_play_url': '第01集\$${_idWithName('第01集.mp4')}',
              },
            ],
          },
        );
      }
      return const NodePanHttpResponse(
        statusCode: 200,
        json: <String, dynamic>{
          'url': 'https://cdn/video.m3u8',
          'header': <String, dynamic>{'Referer': 'https://pan.uc.cn'},
          'format': 'm3u8',
        },
      );
    });

class _FakeBridge implements PlayerChannelBridge {
  final List<String> calls = <String>[];

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    return null;
  }

  @override
  Stream<Map<String, Object?>> events() =>
      const Stream<Map<String, Object?>>.empty();

  @override
  Future<void> dispose() async {}
}

/// 假夸克原生客户端：仅覆盖分享解析与取链（F-P01）。
class _FakeQuarkClient extends QuarkNativeClient {
  @override
  Future<List<QuarkShareFile>> getFileList({
    required String shareUrl,
    required String cookie,
  }) async =>
      <QuarkShareFile>[
        const QuarkShareFile(
          fid: 'f1',
          fileName: 'EP01.mp4',
          shareFidToken: 'tk1',
        ),
      ];

  @override
  Future<QuarkPlayResult> resolvePlayUrl({
    required String shareUrl,
    required String cookie,
    String? preferredFid,
  }) async =>
      const QuarkPlayResult(url: 'https://v/play.m3u8', fileName: 'EP01.mp4');
}

/// 假百度代理客户端（F-P02）。
class _FakeBaiduClient extends BaiduProxyClient {
  @override
  Future<BaiduProxyResponse> parseShareLink({
    required String url,
    String pwd = '',
    String cookie = '',
  }) async =>
      const BaiduProxyResponse(
        success: true,
        data: BaiduProxyPlayData(
          url: 'https://pcs/parse.m3u8',
          type: 'm3u8',
          fileName: 'EP01.mp4',
        ),
      );

  @override
  Future<BaiduProxyResponse> getPlayURL({
    required String shareURL,
    String pwd = '',
    String fsId = '',
    String cookie = '',
    String pcsCookie = '',
  }) async =>
      const BaiduProxyResponse(
        success: true,
        data: BaiduProxyPlayData(
          url: 'https://pcs/play.m3u8',
          type: 'm3u8',
          fileName: 'EP01.mp4',
          headers: <String, String>{'Referer': 'https://pan.baidu.com'},
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final PrefsManager pm = PrefsManager.instance;
  final DateTime t0 = DateTime.utc(2026, 10, 3, 12);
  late CloudPlayItemCacheStore cache;
  late PanPlayer player;
  late _FakeBridge bridge;
  late PlayerController controller;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await pm.init();
  });

  setUp(() async {
    await pm.clearAll();
    cache = CloudPlayItemCacheStore(pm);
    bridge = _FakeBridge();
    controller = PlayerController(
      bridge: bridge,
      backendChain: const <PlayerBackend>[PlayerBackend.media3],
      selectInitialBackend: (_, __) => PlayerBackend.media3,
    );
    player = PanPlayer(
      client: NodePanClient(transport: _happyTransport()),
      cacheStore: cache,
      controller: controller,
    );
  });

  group('channelFor 路由判定（对齐 iOS resolvePlayURL 分支）', () {
    test('Node 托管盘 / 阿里 PG / 原生盘 / 未支持盘', () {
      expect(PanPlayer.channelFor(CloudDriveType.one15), PanPlayChannel.nodePan);
      expect(
        PanPlayer.channelFor(CloudDriveType.baiduNode),
        PanPlayChannel.nodePan,
      );
      expect(PanPlayer.channelFor(CloudDriveType.ali), PanPlayChannel.pgAli);
      expect(PanPlayer.channelFor(CloudDriveType.baidu), PanPlayChannel.native);
      expect(PanPlayer.channelFor(CloudDriveType.quark), PanPlayChannel.native);
      expect(PanPlayer.channelFor(CloudDriveType.uc), PanPlayChannel.native);
      expect(
        PanPlayer.channelFor(CloudDriveType.bilibili),
        PanPlayChannel.unsupported,
      );
    });
  });

  group('通道守卫', () {
    test('阿里云盘 → PG 路链未接线明确报错', () async {
      await expectLater(
        player.resolveShare(CloudDriveType.ali, 'https://pan/ali/s/x'),
        throwsA(
          isA<PanPlayException>().having(
            (PanPlayException e) => e.message,
            'msg',
            contains('PG 4kz 路链'),
          ),
        ),
      );
    });

    test('原生盘 → 原生路链未接线明确报错', () async {
      await expectLater(
        player.resolveShare(CloudDriveType.baidu, 'https://pan.baidu/s/x'),
        throwsA(
          isA<PanPlayException>().having(
            (PanPlayException e) => e.message,
            'msg',
            contains('原生路链尚未接入'),
          ),
        ),
      );
    });

    test('未支持盘（B 站）→ 不支持网盘播放', () async {
      await expectLater(
        player.resolveShare(CloudDriveType.bilibili, 'https://b23.tv/x'),
        throwsA(isA<PanPlayException>()),
      );
    });
  });

  test('resolveShare 返回条目（Node 托管盘）', () async {
    final NodePanShare share = await player.resolveShare(
      CloudDriveType.ucNode,
      'https://pan.uc.cn/s/x',
    );
    expect(share.title, '示例剧');
    expect(share.entries.single.name, '第01集.mp4');
  });

  test('prepare 解析播放地址并写入统一缓存', () async {
    final NodePanShare share = await player.resolveShare(
      CloudDriveType.ucNode,
      'https://pan.uc.cn/s/x',
    );
    final CloudPlayItem item = await player.prepare(
      type: CloudDriveType.ucNode,
      shareUrl: 'https://pan.uc.cn/s/x',
      entry: share.entries.single,
      now: t0,
    );
    expect(item.provider, 'ucNode');
    expect(item.playURL, 'https://cdn/video.m3u8');
    expect(item.compatibilityHint, 'node-proxy');
    expect(item.preparedAt, t0);

    final Map<String, CloudPlayItem> stored = await cache.load();
    expect(stored.length, 1);
    expect(stored.values.single.playURL, 'https://cdn/video.m3u8');
  });

  test('open 以显式 pan 路由打开播放器', () async {
    final NodePanShare share = await player.resolveShare(
      CloudDriveType.ucNode,
      'https://pan.uc.cn/s/x',
    );
    final CloudPlayItem item = await player.open(
      type: CloudDriveType.ucNode,
      shareUrl: 'https://pan.uc.cn/s/x',
      entry: share.entries.single,
      now: t0,
    );
    expect(item.playURL, 'https://cdn/video.m3u8');
    expect(bridge.calls, contains('open'));
    expect(controller.route, PlaybackRoute.pan);
    expect(controller.state, PlayerState.opening);
  });

  test('summary / invalidate 透传缓存语义', () async {
    final NodePanShare share = await player.resolveShare(
      CloudDriveType.ucNode,
      'https://pan.uc.cn/s/x',
    );
    await player.prepare(
      type: CloudDriveType.ucNode,
      shareUrl: 'https://pan.uc.cn/s/x',
      entry: share.entries.single,
      now: t0,
    );
    CloudPlayItemSummary s = await player.summary(
      CloudDriveType.ucNode,
      now: t0.add(const Duration(seconds: 1)),
    );
    expect(s.totalCount, 1);
    expect(s.validPlayURLCount, 1);

    await player.invalidate(
      type: CloudDriveType.ucNode,
      sourceKey: share.entries.single.playID,
      now: t0.add(const Duration(minutes: 1)),
    );
    final Map<String, CloudPlayItem> stored = await cache.load();
    expect(stored.values.single.playURL, isNull);
    expect(
      stored.values.single.source,
      'node-pan-invalidated',
    );

    s = await player.summary(
      CloudDriveType.ucNode,
      now: t0.add(const Duration(minutes: 2)),
    );
    expect(s.validPlayURLCount, 0);

    await player.clear(CloudDriveType.ucNode);
    expect(await cache.load(), isEmpty);
  });

  test('open 后缓存键 = provider|sourceKey', () async {
    final NodePanShare share = await player.resolveShare(
      CloudDriveType.one15,
      'https://115.com/s/x',
    );
    await player.open(
      type: CloudDriveType.one15,
      shareUrl: 'https://115.com/s/x',
      entry: share.entries.single,
      sourceKey: 'svc-1',
      now: t0,
    );
    expect((await cache.load()).keys, <String>['115|svc-1']);
  });

  group('夸克原生链（F-P01）', () {
    late PanPlayer quarkPlayer;

    setUp(() {
      quarkPlayer = PanPlayer(
        client: NodePanClient(transport: _happyTransport()),
        cacheStore: cache,
        controller: controller,
        quarkClient: _FakeQuarkClient(),
        cookieFor: (CloudDriveType _) async => 'k=v',
      );
    });

    test('resolveShare → 文件条目（fid 作 playID）', () async {
      final NodePanShare share = await quarkPlayer.resolveShare(
        CloudDriveType.quark,
        'https://pan.quark.cn/s/abc',
      );
      expect(share.title, '夸克分享');
      expect(share.entries.single.playID, 'f1');
      expect(share.entries.single.name, 'EP01.mp4');
    });

    test('prepare → 取链并落缓存（带 Cookie/Referer 头）', () async {
      final CloudPlayItem item = await quarkPlayer.prepare(
        type: CloudDriveType.quark,
        shareUrl: 'https://pan.quark.cn/s/abc',
        entry: const NodePanEntry(playID: 'f1', name: 'EP01.mp4'),
        now: t0,
      );
      expect(item.playURL, 'https://v/play.m3u8');
      expect(item.headers['Cookie'], 'k=v');
      expect(item.source, 'quark-native');
      expect(item.compatibilityHint, 'quark-native');
      expect((await cache.load()).length, 1);
    });

    test('UC 原生链仍未接入 → 明确报错（逐步接入）', () async {
      await expectLater(
        quarkPlayer.resolveShare(CloudDriveType.uc, 'https://drive.uc.cn/s/x'),
        throwsA(isA<PanPlayException>()),
      );
    });
  });

  group('百度原生链（F-P02，Worker 代理）', () {
    late PanPlayer baiduPlayer;

    setUp(() {
      baiduPlayer = PanPlayer(
        client: NodePanClient(transport: _happyTransport()),
        cacheStore: cache,
        controller: controller,
        baiduClient: _FakeBaiduClient(),
        cookieFor: (CloudDriveType _) async => 'k=v',
      );
    });

    test('resolveShare → 单条目（文件名为分享标题）', () async {
      final NodePanShare share = await baiduPlayer.resolveShare(
        CloudDriveType.baidu,
        'https://pan.baidu.com/s/1abc',
      );
      expect(share.title, 'EP01.mp4');
      expect(share.entries.single.name, 'EP01.mp4');
    });

    test('prepare → 取链并带代理响应头 + Cookie', () async {
      final CloudPlayItem item = await baiduPlayer.prepare(
        type: CloudDriveType.baidu,
        shareUrl: 'https://pan.baidu.com/s/1abc',
        entry: const NodePanEntry(playID: 'baidu', name: 'EP01.mp4'),
        now: t0,
      );
      expect(item.playURL, 'https://pcs/play.m3u8');
      expect(item.headers['Referer'], 'https://pan.baidu.com');
      expect(item.headers['Cookie'], 'k=v');
      expect(item.source, 'baidu-worker');
    });

    test('默认无代理 → 映射为明确报错（百度代理未接入）', () async {
      final PanPlayer noProxy = PanPlayer(
        client: NodePanClient(transport: _happyTransport()),
        cacheStore: cache,
        controller: controller,
        cookieFor: (CloudDriveType _) async => '',
      );
      await expectLater(
        noProxy.resolveShare(CloudDriveType.baidu, 'https://pan.baidu.com/s/1a'),
        throwsA(isA<PanPlayException>()),
      );
    });
  });
}
