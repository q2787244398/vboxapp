/// 网盘登录网关 · Node 常驻系统实现（批次 F · F-05）。
///
/// 承接 F-02 定义的 [CloudDriveLoginGateway] 接缝：
/// - **B 站扫码**（`CloudDriveType.bilibili`）走 Node `/website/api/bili/login/*`
///   （[BiliAuthClient]），登录成功后由 [NodeCredentialSyncService.saveProfile]
///   把 Node 侧 Cookie 拉回本机安全存储（对齐 iOS `BiliAuthManager`）；
/// - 其余网盘 / 方式暂未接线，行为与 [UnavailableCloudDriveLoginGateway] 一致
///   （文案分档：Node 档报「Node 常驻系统未就绪」，原生档报「原生登录链路尚未接入」）。
///
/// 说明：B 站二维码由 Node 服务端直接返回图片（`qrImage` data URL），
/// 无需本地 QR 编码依赖；缺图时 UI 展示占位。
library;

import '../../../data/datasources/remote/bili_auth_client.dart';
import '../../../data/datasources/remote/node_credential_sync_service.dart';
import '../../../domain/entities/cloud/bili_auth.dart';
import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/cloud_drive_login.dart';
import 'login_gateway.dart';

/// Node 常驻系统登录网关（当前覆盖 B 站扫码）。
class NodeCloudDriveLoginGateway implements CloudDriveLoginGateway {
  /// 构造（[biliClient] / [credentialSync] 供测试注入）。
  NodeCloudDriveLoginGateway({
    BiliAuthClient? biliClient,
    NodeCredentialSyncService? credentialSync,
  })  : _bili = biliClient ?? BiliAuthClient(),
        _credentialSync = credentialSync;

  final BiliAuthClient _bili;
  final NodeCredentialSyncService? _credentialSync;

  /// 该网关是否覆盖给定网盘 / 方式（当前仅 B 站扫码）。
  static bool supports(CloudDriveType type, CloudDriveLoginMode mode) =>
      type == CloudDriveType.bilibili && mode.isQr;

  String _unavailableMessage(CloudDriveLoginMode mode) =>
      mode.usesNode ? 'Node 常驻系统未就绪' : '原生登录链路尚未接入';

  @override
  Future<CloudDriveQrTask> startQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
  }) async {
    if (!supports(type, mode)) {
      throw CloudDriveLoginException(_unavailableMessage(mode));
    }
    final BiliQrStart start = await _bili.startQrLogin();
    return (taskId: start.taskId, qrDataUrl: start.qrDataUrl ?? '');
  }

  @override
  Future<CloudDriveLoginPhase> pollQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String taskId,
  }) async {
    if (!supports(type, mode)) {
      throw CloudDriveLoginException(_unavailableMessage(mode));
    }
    final BiliPollResult result = await _bili.pollQrLogin(taskId);

    if (result.status == BiliAuthStatus.success) {
      // 对齐 iOS：cookie 已写入 Node db，拉回本机安全存储（失败不阻断登录）。
      final NodeCredentialSyncService? sync = _credentialSync;
      if (sync != null) {
        try {
          await sync.saveProfile();
        } catch (_) {
          // 凭据回收失败不影响「登录成功」态展示（网关失败不冒泡）。
        }
      }
      return CloudDriveLoginPhase.success;
    }

    if (result.status == BiliAuthStatus.expired) {
      throw CloudDriveLoginException(
        result.msg.isEmpty ? '二维码已过期，请重试' : result.msg,
      );
    }
    if (result.status == BiliAuthStatus.error) {
      throw CloudDriveLoginException(
        result.msg.isEmpty ? '扫码登录失败' : result.msg,
      );
    }
    if (result.terminal && result.status == BiliAuthStatus.waiting) {
      throw CloudDriveLoginException(
        result.msg.isEmpty ? '扫码登录已结束' : result.msg,
      );
    }
    return result.status.toPhase();
  }

  @override
  Future<void> cancelQrLogin(String taskId) async {
    // 取消为幂等操作；仅 B 站走 Node 任务，其余任务无副作用。
    await _bili.cancelQrLogin(taskId);
  }

  @override
  Future<String> sendSmsCode({
    required CloudDriveType type,
    required String phone,
  }) async =>
      throw const CloudDriveLoginException('Node 常驻系统未就绪');

  @override
  Future<void> submitSmsCode({
    required CloudDriveType type,
    required String taskId,
    required String code,
  }) async =>
      throw const CloudDriveLoginException('Node 常驻系统未就绪');

  @override
  Future<void> submitAccountLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String account,
    required String password,
  }) async =>
      throw const CloudDriveLoginException('Node 常驻系统未就绪');
}

/// 缺省登录网关工厂：按网盘 / 方式路由到已接入实现。
///
/// - B 站扫码（`bilibili` + 扫码类）→ [NodeCloudDriveLoginGateway]（走 Node
///   常驻系统，成功后由 [NodeCredentialSyncService.saveProfile] 回收 Cookie）；
/// - 其余尚未接线的档位 → [UnavailableCloudDriveLoginGateway]（文案分档对齐 iOS）。
CloudDriveLoginGateway defaultCloudDriveLoginGateway(
  CloudDriveType type,
  CloudDriveLoginMode mode,
) {
  if (NodeCloudDriveLoginGateway.supports(type, mode)) {
    return NodeCloudDriveLoginGateway(
      credentialSync: NodeCredentialSyncService(
        client: LocalNodeCredentialApiClient(),
      ),
    );
  }
  return const UnavailableCloudDriveLoginGateway();
}
