/// 网盘播放（pan 模式）编排单测（批次 F · F-08）。
///
/// 覆盖：路由通道判定 / Node 托管盘解析 / 缓存落盘 / 显式 pan 路由打开 / 汇总与失效。
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/data/datasources/local/cloud_drive_credential_store.dart';
import 'package:vbox/data/datasources/local/cloud_play_item_cache_store.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/data/datasources/remote/aliyun_adrive_client.dart';
import 'package:vbox/data/datasources/remote/baidu_ibox_client.dart';
import 'package:vbox/data/datasources/remote/node_pan_client.dart';
import 'package:vbox/data/datasources/remote/quark_native_client.dart';
import 'package:vbox/data/datasources/remote/uc_native_client.dart';
import 'package:vbox/domain/entities/cloud/cloud_drive.dart';
import 'package:vbox/domain/entities/cloud/cloud_play_item.dart';
import 'package:vbox/domain/entities/cloud/node_pan.dart';
import 'package:vbox/domain/entities/cloud/pg_auto.dart';
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
    String? routePreference,
  }) async =>
      const QuarkPlayResult(url: 'https://v/play.m3u8', fileName: 'EP01.mp4');
}

/// 假 UC 原生客户端（F-P03）：仅覆盖分享解析与取链。
class _FakeUcClient extends UcNativeClient {
  @override
  Future<List<UcShareFile>> getFileList({
    required String shareUrl,
    required String cookie,
    String? tvToken,
  }) async =>
      <UcShareFile>[
        const UcShareFile(fid: 'u1', fileName: 'EP01.mp4', shareFidToken: 'tk1'),
      ];

  @override
  Future<UcPlayResult> resolvePlayUrl({
    required String shareUrl,
    required String cookie,
    String? preferredFid,
    String? tvToken,
  }) async =>
      const UcPlayResult(
        url: 'https://uc/play.m3u8',
        headers: <String, String>{'Referer': 'https://drive.uc.cn/'},
        source: 'v2-play',
      );
}

/// 假百度 iBox 客户端（F-P02）：多文件选集 + 取链。
class _FakeBaiduIBoxClient extends BaiduIBoxClient {
  @override
  Future<List<BaiduFileItem>> getFileList({
    required String shareUrl,
    required String cookie,
  }) async =>
      <BaiduFileItem>[
        const BaiduFileItem(fsId: '111', name: 'EP01.mp4'),
        const BaiduFileItem(fsId: '222', name: 'EP02.mp4'),
      ];

  @override
  Future<BaiduPlayResult> resolvePlayURL({
    required String shareUrl,
    required String bduss,
    required String fsId,
    String pcsCookie = '',
  }) async =>
      const BaiduPlayResult(
        url: 'https://ibox/play.m3u8',
        headers: <String, String>{'Referer': 'https://pan.baidu.com/'},
        source: 'main-transfer-locatedownload',
      );
}

/// 假百度 iBox 客户端（取链失败，用于错误映射断言）。
class _FailingBaiduIBoxClient extends BaiduIBoxClient {
  @override
  Future<BaiduPlayResult> resolvePlayURL({
    required String shareUrl,
    required String bduss,
    required String fsId,
    String pcsCookie = '',
  }) async =>
      throw const BaiduIBoxException('百度登录态正常，但未取得用户态 bdstoken');
}

/// 假阿里云盘 PG 客户端（F-P09）：文件列表 + 取链。
class _FakeAliyunClient extends AliyunAdriveClient {
  @override
  Future<List<AliyunShareFile>> listPlayableFiles({
    required String shareUrl,
    required String refreshToken,
  }) async =>
      <AliyunShareFile>[
        const AliyunShareFile(
          fileId: 'ali1',
          name: 'EP01.mp4',
          category: 'video',
        ),
        const AliyunShareFile(
          fileId: 'ali2',
          name: 'EP02.mp4',
          category: 'video',
        ),
      ];

  @override
  Future<AliyunPlayResult> resolvePlayUrl({
    required String shareUrl,
    required String refreshToken,
    String? preferredFileId,
    PgAutoConfig pgConfig = PgAutoConfig.defaults,
  }) async =>
      const AliyunPlayResult(
        url: 'https://cdn/ali.m3u8',
        headers: <String, String>{},
        source: 'ali-share-transcode',
        fileName: 'EP01.mp4',
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
    test('阿里云盘未授权 → 明确报错（缺 Refresh Token）', () async {
      await expectLater(
        player.resolveShare(CloudDriveType.ali, 'https://www.alipan.com/s/x'),
        throwsA(
          isA<PanPlayException>().having(
            (PanPlayException e) => e.message,
            'msg',
            contains('未授权'),
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
  });

  group('UC 原生链（F-P03）', () {
    late PanPlayer ucPlayer;

    setUp(() {
      ucPlayer = PanPlayer(
        client: NodePanClient(transport: _happyTransport()),
        cacheStore: cache,
        controller: controller,
        ucClient: _FakeUcClient(),
        cookieFor: (CloudDriveType _) async => 'k=v',
      );
    });

    test('resolveShare → 文件条目（fid 作 playID）', () async {
      final NodePanShare share = await ucPlayer.resolveShare(
        CloudDriveType.uc,
        'https://drive.uc.cn/s/abc',
      );
      expect(share.title, 'UC分享');
      expect(share.entries.single.playID, 'u1');
      expect(share.entries.single.name, 'EP01.mp4');
    });

    test('prepare → 取链并落缓存（带 Cookie/Referer 头）', () async {
      final CloudPlayItem item = await ucPlayer.prepare(
        type: CloudDriveType.uc,
        shareUrl: 'https://drive.uc.cn/s/abc',
        entry: const NodePanEntry(playID: 'u1', name: 'EP01.mp4'),
        now: t0,
      );
      expect(item.playURL, 'https://uc/play.m3u8');
      expect(item.headers['Referer'], 'https://drive.uc.cn/');
      expect(item.source, 'uc-native');
      expect(item.compatibilityHint, 'uc-native');
      expect((await cache.load()).length, 1);
    });
  });

  group('百度原生链（F-P02，iBox 本机链）', () {
    late PanPlayer baiduPlayer;

    setUp(() {
      baiduPlayer = PanPlayer(
        client: NodePanClient(transport: _happyTransport()),
        cacheStore: cache,
        controller: controller,
        baiduIBoxClient: _FakeBaiduIBoxClient(),
        cookieFor: (CloudDriveType _) async => 'BDUSS=u',
      );
    });

    test('resolveShare → 多文件选集（fsId 作 playID）', () async {
      final NodePanShare share = await baiduPlayer.resolveShare(
        CloudDriveType.baidu,
        'https://pan.baidu.com/s/1abc',
      );
      expect(share.title, '百度分享');
      expect(share.entries.length, 2);
      expect(share.entries.first.playID, '111');
      expect(share.entries.first.name, 'EP01.mp4');
    });

    test('prepare → iBox 取链（headers/source 取自结果）', () async {
      final CloudPlayItem item = await baiduPlayer.prepare(
        type: CloudDriveType.baidu,
        shareUrl: 'https://pan.baidu.com/s/1abc',
        entry: const NodePanEntry(playID: '111', name: 'EP01.mp4'),
        now: t0,
      );
      expect(item.playURL, 'https://ibox/play.m3u8');
      expect(item.headers['Referer'], 'https://pan.baidu.com/');
      expect(item.source, 'main-transfer-locatedownload');
      expect(item.compatibilityHint, 'main-transfer-locatedownload');
    });

    test('取链失败 → BaiduIBoxException 映射为 PanPlayException', () async {
      final PanPlayer failing = PanPlayer(
        client: NodePanClient(transport: _happyTransport()),
        cacheStore: cache,
        controller: controller,
        baiduIBoxClient: _FailingBaiduIBoxClient(),
        cookieFor: (CloudDriveType _) async => 'BDUSS=u',
      );
      await expectLater(
        failing.prepare(
          type: CloudDriveType.baidu,
          shareUrl: 'https://pan.baidu.com/s/1abc',
          entry: const NodePanEntry(playID: '111', name: 'EP01.mp4'),
          now: t0,
        ),
        throwsA(
          isA<PanPlayException>().having(
            (PanPlayException e) => e.message,
            'msg',
            contains('未取得用户态 bdstoken'),
          ),
        ),
      );
    });
  });

  group('阿里云盘 PG 4kz（F-P09）', () {
    late PanPlayer aliPlayer;

    setUp(() async {
      await CloudDriveCredentialStore(pm).save(
        CloudDriveCredential(
          driveType: CloudDriveType.ali.id,
          refreshToken: 'rt',
          updatedAt: DateTime.now(),
        ),
      );
      aliPlayer = PanPlayer(
        client: NodePanClient(transport: _happyTransport()),
        cacheStore: cache,
        controller: controller,
        aliyunClient: _FakeAliyunClient(),
      );
    });

    test('resolveShare → 文件条目（fileId 作 playID）', () async {
      final NodePanShare share = await aliPlayer.resolveShare(
        CloudDriveType.ali,
        'https://www.alipan.com/s/abc',
      );
      expect(share.title, '阿里云盘分享');
      expect(share.entries.length, 2);
      expect(share.entries.first.playID, 'ali1');
      expect(share.entries.first.name, 'EP01.mp4');
    });

    test('prepare → PG 取链（source 取自结果）', () async {
      final CloudPlayItem item = await aliPlayer.prepare(
        type: CloudDriveType.ali,
        shareUrl: 'https://www.alipan.com/s/abc',
        entry: const NodePanEntry(playID: 'ali1', name: 'EP01.mp4'),
        now: t0,
      );
      expect(item.playURL, 'https://cdn/ali.m3u8');
      expect(item.source, 'ali-share-transcode');
      expect(item.fileName, 'EP01.mp4');
      expect((await cache.load()).length, 1);
    });
  });
}
