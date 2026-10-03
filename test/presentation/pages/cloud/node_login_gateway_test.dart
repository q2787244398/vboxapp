/// 表现层单测：Node 常驻系统登录网关（批次 F · F-05）。
///
/// 验证 [NodeCloudDriveLoginGateway] 的 B 站扫码链：支持判定、start/poll 阶段
/// 映射、成功时回收凭据（saveProfile）、以及按方式分档的「未就绪」文案。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/data/datasources/local/cloud_drive_credential_store.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/data/datasources/remote/bili_auth_client.dart';
import 'package:vbox/data/datasources/remote/node_credential_sync_service.dart';
import 'package:vbox/domain/entities/cloud/bili_auth.dart';
import 'package:vbox/domain/entities/cloud/cloud_drive.dart';
import 'package:vbox/domain/entities/cloud/cloud_drive_login.dart';
import 'package:vbox/presentation/pages/cloud/login_gateway.dart';
import 'package:vbox/presentation/pages/cloud/node_login_gateway.dart';

/// 假 B 站传输：按路径返回预设响应。
class _FakeBiliTransport implements BiliAuthTransport {
  _FakeBiliTransport(this.handler);

  final Map<String, dynamic> Function(String method, String path) handler;

  @override
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async =>
      handler(method, path);
}

/// 记录调用的 Node 凭据客户端。
class _RecordingCredentialClient implements NodeCredentialApiClient {
  final List<String> calls = <String>[];

  @override
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    calls.add('$method $path');
    return <String, dynamic>{'code': 0};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PrefsManager pm;
  late CloudDriveCredentialStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    pm = PrefsManager.instance;
    await pm.init();
  });

  setUp(() async {
    await pm.clearAll();
    store = CloudDriveCredentialStore(pm);
  });

  NodeCloudDriveLoginGateway gatewayWith(
    Map<String, dynamic> Function(String method, String path) handler, {
    _RecordingCredentialClient? credentialClient,
  }) =>
      NodeCloudDriveLoginGateway(
        biliClient: BiliAuthClient(transport: _FakeBiliTransport(handler)),
        credentialSync: credentialClient == null
            ? null
            : NodeCredentialSyncService(
                store: store,
                client: credentialClient,
              ),
      );

  group('supports / 文案', () {
    test('仅 B 站扫码类受支持', () {
      expect(
        NodeCloudDriveLoginGateway.supports(
          CloudDriveType.bilibili,
          CloudDriveLoginMode.nodeQr,
        ),
        isTrue,
      );
      expect(
        NodeCloudDriveLoginGateway.supports(
          CloudDriveType.bilibili,
          CloudDriveLoginMode.nativeQr,
        ),
        isTrue,
      );
      expect(
        NodeCloudDriveLoginGateway.supports(
          CloudDriveType.ali,
          CloudDriveLoginMode.nativeQr,
        ),
        isFalse,
      );
      expect(
        NodeCloudDriveLoginGateway.supports(
          CloudDriveType.bilibili,
          CloudDriveLoginMode.nodeSms,
        ),
        isFalse,
      );
    });

    test('不支持档：Node 方式报「未就绪」，原生方式报「未接入」', () async {
      final NodeCloudDriveLoginGateway gateway = gatewayWith((_, __) => <String, dynamic>{});
      await expectLater(
        gateway.startQrLogin(
          type: CloudDriveType.bilibili,
          mode: CloudDriveLoginMode.nodeSms,
        ),
        throwsA(
          isA<CloudDriveLoginException>().having(
            (CloudDriveLoginException e) => e.message,
            'message',
            'Node 常驻系统未就绪',
          ),
        ),
      );
      await expectLater(
        gateway.startQrLogin(
          type: CloudDriveType.ali,
          mode: CloudDriveLoginMode.nativeQr,
        ),
        throwsA(
          isA<CloudDriveLoginException>().having(
            (CloudDriveLoginException e) => e.message,
            'message',
            '原生登录链路尚未接入',
          ),
        ),
      );
    });
  });

  group('startQrLogin', () {
    test('B 站扫码返回 taskId 与二维码 data URL', () async {
      final NodeCloudDriveLoginGateway gateway = gatewayWith((_, __) =>
          <String, dynamic>{
            'code': 0,
            'taskId': 'T-1',
            'qrImage': 'data:image/png;base64,AAAA',
          });
      final CloudDriveQrTask task = await gateway.startQrLogin(
        type: CloudDriveType.bilibili,
        mode: CloudDriveLoginMode.nativeQr,
      );
      expect(task.taskId, 'T-1');
      expect(task.qrDataUrl, 'data:image/png;base64,AAAA');
    });

    test('缺图时 qrDataUrl 为空串（UI 展示占位）', () async {
      final NodeCloudDriveLoginGateway gateway = gatewayWith((_, __) =>
          <String, dynamic>{'code': 0, 'taskId': 'T-2'});
      final CloudDriveQrTask task = await gateway.startQrLogin(
        type: CloudDriveType.bilibili,
        mode: CloudDriveLoginMode.nodeQr,
      );
      expect(task.qrDataUrl, '');
    });
  });

  group('pollQrLogin', () {
    test('成功：返回 success 并回收凭据（saveProfile → GET credentials）', () async {
      final _RecordingCredentialClient credential = _RecordingCredentialClient();
      final NodeCloudDriveLoginGateway gateway = gatewayWith(
        (_, __) => <String, dynamic>{'status': 'success', 'terminal': true},
        credentialClient: credential,
      );
      final CloudDriveLoginPhase phase = await gateway.pollQrLogin(
        type: CloudDriveType.bilibili,
        mode: CloudDriveLoginMode.nativeQr,
        taskId: 'T',
      );
      expect(phase, CloudDriveLoginPhase.success);
      expect(credential.calls, <String>['GET /website/api/credentials']);
    });

    test('已扫码 → scanned 阶段，不回收凭据', () async {
      final _RecordingCredentialClient credential = _RecordingCredentialClient();
      final NodeCloudDriveLoginGateway gateway = gatewayWith(
        (_, __) => <String, dynamic>{'status': 'waiting', 'msg': '已扫码，请确认'},
        credentialClient: credential,
      );
      final CloudDriveLoginPhase phase = await gateway.pollQrLogin(
        type: CloudDriveType.bilibili,
        mode: CloudDriveLoginMode.nativeQr,
        taskId: 'T',
      );
      expect(phase, CloudDriveLoginPhase.scanned);
      expect(credential.calls, isEmpty);
    });

    test('过期 / 失败：抛错并携带服务端 msg', () async {
      final NodeCloudDriveLoginGateway expired = gatewayWith(
        (_, __) => <String, dynamic>{'status': 'expired', 'msg': '二维码过期'},
      );
      await expectLater(
        expired.pollQrLogin(
          type: CloudDriveType.bilibili,
          mode: CloudDriveLoginMode.nativeQr,
          taskId: 'T',
        ),
        throwsA(
          isA<CloudDriveLoginException>()
              .having((CloudDriveLoginException e) => e.message, 'message', '二维码过期'),
        ),
      );

      final NodeCloudDriveLoginGateway failed = gatewayWith(
        (_, __) => <String, dynamic>{'status': 'error', 'msg': '风控'},
      );
      await expectLater(
        failed.pollQrLogin(
          type: CloudDriveType.bilibili,
          mode: CloudDriveLoginMode.nativeQr,
          taskId: 'T',
        ),
        throwsA(
          isA<CloudDriveLoginException>()
              .having((CloudDriveLoginException e) => e.message, 'message', '风控'),
        ),
      );
    });

    test('waiting 且 terminal=true（无 msg）→ 抛「扫码登录已结束」', () async {
      final NodeCloudDriveLoginGateway gateway = gatewayWith(
        (_, __) => <String, dynamic>{'status': 'waiting', 'terminal': true},
      );
      await expectLater(
        gateway.pollQrLogin(
          type: CloudDriveType.bilibili,
          mode: CloudDriveLoginMode.nativeQr,
          taskId: 'T',
        ),
        throwsA(
          isA<CloudDriveLoginException>().having(
            (CloudDriveLoginException e) => e.message,
            'message',
            '扫码登录已结束',
          ),
        ),
      );
    });
  });

  test('defaultCloudDriveLoginGateway：B 站扫码路由 Node 网关，其余回退未接入', () {
    expect(
      defaultCloudDriveLoginGateway(
        CloudDriveType.bilibili,
        CloudDriveLoginMode.nodeQr,
      ),
      isA<NodeCloudDriveLoginGateway>(),
    );
    expect(
      defaultCloudDriveLoginGateway(
        CloudDriveType.ali,
        CloudDriveLoginMode.nativeQr,
      ),
      isA<UnavailableCloudDriveLoginGateway>(),
    );
    // B 站短信档不受支持 → 回退未接入。
    expect(
      defaultCloudDriveLoginGateway(
        CloudDriveType.bilibili,
        CloudDriveLoginMode.nodeSms,
      ),
      isA<UnavailableCloudDriveLoginGateway>(),
    );
  });

  test('cancelQrLogin 幂等：失败不冒泡', () async {
    final NodeCloudDriveLoginGateway gateway = gatewayWith((_, __) {
      throw const BiliAuthException('boom');
    });
    await expectLater(gateway.cancelQrLogin('T'), completes);
  });

  test('短信 / 账号入口：统一报 Node 未就绪', () async {
    final NodeCloudDriveLoginGateway gateway = gatewayWith((_, __) => <String, dynamic>{});
    await expectLater(
      gateway.sendSmsCode(type: CloudDriveType.bilibili, phone: '1'),
      throwsA(isA<CloudDriveLoginException>()),
    );
    await expectLater(
      gateway.submitSmsCode(
        type: CloudDriveType.bilibili,
        taskId: 'T',
        code: '1',
      ),
      throwsA(isA<CloudDriveLoginException>()),
    );
    await expectLater(
      gateway.submitAccountLogin(
        type: CloudDriveType.bilibili,
        mode: CloudDriveLoginMode.nodeAccount,
        account: 'a',
        password: 'p',
      ),
      throwsA(isA<CloudDriveLoginException>()),
    );
  });
}
