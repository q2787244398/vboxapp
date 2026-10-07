/// 网盘登录网关 · Node 常驻系统实现（批次 F · F-P16）。
///
/// 承接 F-02 定义的 [CloudDriveLoginGateway] 接缝：
/// - **B 站扫码**（`CloudDriveType.bilibili`）走 Node `/website/api/bili/login/*`
///   （[BiliAuthClient]）；
/// - **通用扫码**（115 / 夸克Node / 百度Node / UCNode）走 `/website/api/login/*`
///   （[NodeLoginClient]）；
/// - **短信验证码**（光鸭 / 139 / 迅雷）走各盘 `/website/api/<pan>/sms/*`；
/// - **账号密码**（123 / 189）走各盘 `/website/api/<pan>/account`；
/// 登录成功后统一由 [NodeCredentialSyncService.saveProfile] 把 Node 侧凭据
/// 拉回本机安全存储（对齐 iOS `NodeCredentialSyncService.performPull`）。
///
/// 未覆盖（登记待补）：
/// - 蜗牛（`woniu4k`）需图形验证码（`/woniou4k/verify` 图片 + verify 输入），
///   现有网关接口无 verify 传参位，待 UI 扩展后接入；
/// - UCNode 第 2 步 TV Token（`provider:"ucToken"`）需多步 UI 编排，本段先接
///   第 1 步 Cookie（`ucCookie`，核心登录态）；
/// - 139 滑块验证码（`captchaUrl`）需内嵌 WebView（Web-R3）。
library;

import '../../../data/datasources/remote/bili_auth_client.dart';
import '../../../data/datasources/remote/node_credential_sync_service.dart';
import '../../../data/datasources/remote/node_login_client.dart';
import '../../../domain/entities/cloud/bili_auth.dart';
import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/cloud_drive_login.dart';
import '../../../domain/entities/cloud/node_login.dart';
import 'aliyun_pg_login_gateway.dart';
import 'login_gateway.dart';
import 'native_cloud_drive_login_gateway.dart';

/// Node 常驻系统登录网关（B 站 + 9 家 Node 托管盘）。
class NodeCloudDriveLoginGateway implements CloudDriveLoginGateway {
  /// 构造（[biliClient] / [nodeClient] / [credentialSync] 供测试注入）。
  NodeCloudDriveLoginGateway({
    BiliAuthClient? biliClient,
    NodeLoginClient? nodeClient,
    NodeCredentialSyncService? credentialSync,
  })  : _bili = biliClient ?? BiliAuthClient(),
        _node = nodeClient ?? NodeLoginClient(),
        _credentialSync = credentialSync;

  final BiliAuthClient _bili;
  final NodeLoginClient _node;
  final NodeCredentialSyncService? _credentialSync;

  /// 短信/账号登录的跨调用暂存（139 headers、139/迅雷 phone、光鸭 taskId）。
  final Map<CloudDriveType, String> _smsTask = <CloudDriveType, String>{};
  final Map<CloudDriveType, String> _smsPhone = <CloudDriveType, String>{};
  final Map<CloudDriveType, Map<String, String>> _loginHeaders =
      <CloudDriveType, Map<String, String>>{};

  /// 短信登录所需滑块验证页地址（139 `captchaUrl`）。
  final Map<CloudDriveType, String> _captchaUrl = <CloudDriveType, String>{};

  /// 蜗牛图形验证码的服务端 taskId（`loadAccountCaptcha` 缓存）。
  final Map<CloudDriveType, String> _accountCaptchaTask =
      <CloudDriveType, String>{};

  /// 该网关是否覆盖给定网盘 / 方式。
  static bool supports(CloudDriveType type, CloudDriveLoginMode mode) {
    if (type == CloudDriveType.bilibili) return mode.isQr;
    return switch (mode) {
      CloudDriveLoginMode.nodeQr =>
        NodeLoginRouting.qrProviders.containsKey(type),
      CloudDriveLoginMode.nodeSms => NodeLoginRouting.smsTypes.contains(type),
      CloudDriveLoginMode.nodeAccount =>
        NodeLoginRouting.accountTypes.contains(type),
      _ => false,
    };
  }

  String _unavailableMessage(CloudDriveLoginMode mode) =>
      mode.usesNode ? 'Node 常驻系统未就绪' : '原生登录链路尚未接入';

  /// 登录成功后回收凭据（失败不冒泡，对齐 iOS 容错）。
  Future<void> _recover() async {
    final NodeCredentialSyncService? sync = _credentialSync;
    if (sync == null) return;
    try {
      await sync.saveProfile();
    } catch (_) {
      // 凭据回收失败不影响「登录成功」态展示。
    }
  }

  static bool _isBili(CloudDriveType type, CloudDriveLoginMode mode) =>
      type == CloudDriveType.bilibili && mode.isQr;

  // ─────────────── 扫码 ───────────────

  @override
  Future<CloudDriveQrTask> startQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    String? providerOverride,
  }) async {
    if (_isBili(type, mode) && providerOverride == null) {
      final BiliQrStart start = await _bili.startQrLogin();
      return (taskId: start.taskId, qrDataUrl: start.qrDataUrl ?? '');
    }
    final String? provider =
        providerOverride ?? NodeLoginRouting.qrProviderFor(type);
    if (provider == null || !mode.isQr) {
      throw CloudDriveLoginException(_unavailableMessage(mode));
    }
    final ({String qrDataUrl, String taskId}) r =
        await _node.startQr(provider);
    return (taskId: r.taskId, qrDataUrl: r.qrDataUrl);
  }

  @override
  Future<CloudDriveLoginPhase> pollQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String taskId,
    String? providerOverride,
  }) async {
    if (_isBili(type, mode) && providerOverride == null) {
      return _pollBili(taskId);
    }
    final String? provider =
        providerOverride ?? NodeLoginRouting.qrProviderFor(type);
    if (provider == null || !mode.isQr) {
      throw CloudDriveLoginException(_unavailableMessage(mode));
    }
    final NodeLoginPoll poll =
        await _node.pollQr(provider: provider, taskId: taskId);
    if (poll.status == 'success') {
      await _recover();
      return CloudDriveLoginPhase.success;
    }
    if (poll.status == 'expired' || poll.status == 'error') {
      throw CloudDriveLoginException(
        poll.msg.isEmpty ? '二维码已过期，请重试' : poll.msg,
      );
    }
    if (poll.terminal) {
      throw CloudDriveLoginException(
        poll.msg.isEmpty ? '扫码登录已结束' : poll.msg,
      );
    }
    return _phaseFor(poll.status, poll.msg);
  }

  Future<CloudDriveLoginPhase> _pollBili(String taskId) async {
    final BiliPollResult result = await _bili.pollQrLogin(taskId);
    if (result.status == BiliAuthStatus.success) {
      await _recover();
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

  static CloudDriveLoginPhase _phaseFor(String status, String msg) {
    if (status == 'exchanging') return CloudDriveLoginPhase.exchanging;
    if (status == 'scanned' || status == 'confirm') {
      return CloudDriveLoginPhase.scanned;
    }
    if (msg.contains('已扫码') || msg.contains('请确认')) {
      return CloudDriveLoginPhase.scanned;
    }
    return CloudDriveLoginPhase.waitingScan;
  }

  @override
  Future<void> cancelQrLogin(String taskId) async {
    // 取消为幂等操作；B 站与通用扫码各自清理任务。
    await _bili.cancelQrLogin(taskId);
    await _node.cancelQr(taskId);
  }

  // ─────────────── 短信验证码 ───────────────

  @override
  Future<String> sendSmsCode({
    required CloudDriveType type,
    required String phone,
  }) async {
    switch (type) {
      case CloudDriveType.guangya:
        final String taskId = await _node.guangyaSendSms(phone);
        _smsTask[type] = taskId;
        return taskId;
      case CloudDriveType.pan139:
        final ({String captchaUrl, Map<String, String> headers, String msg}) r =
            await _node.new139SendSms(phone);
        _loginHeaders[type] = r.headers;
        _smsPhone[type] = phone;
        // 139 若触发滑块，缓存 captchaUrl 供 UI 内嵌 WebView 过滑块（Web-R3）。
        if (r.captchaUrl.isNotEmpty) {
          _captchaUrl[type] = r.captchaUrl;
        } else {
          _captchaUrl.remove(type);
        }
        // Node 139 不返回 taskId（后续登录以 phone+headers 提交）。
        return '';
      case CloudDriveType.xunlei:
        await _node.thunderSendSms(phone);
        _smsPhone[type] = phone;
        return '';
      default:
        throw const CloudDriveLoginException('该网盘不支持验证码登录');
    }
  }

  @override
  Future<void> submitSmsCode({
    required CloudDriveType type,
    required String taskId,
    required String code,
  }) async {
    switch (type) {
      case CloudDriveType.guangya:
        final String effective =
            taskId.isNotEmpty ? taskId : (_smsTask[type] ?? '');
        await _node.guangyaLoginSms(taskId: effective, code: code);
      case CloudDriveType.pan139:
        await _node.new139Login(
          phone: _smsPhone[type] ?? '',
          code: code,
          headers: _loginHeaders[type] ?? const <String, String>{},
        );
      case CloudDriveType.xunlei:
        await _node.thunderLoginSms(code);
      default:
        throw const CloudDriveLoginException('该网盘不支持验证码登录');
    }
    await _recover();
  }

  // ─────────────── 账号密码 ───────────────

  @override
  Future<void> submitAccountLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String account,
    required String password,
    String captchaCode = '',
  }) async {
    switch (type) {
      case CloudDriveType.pan123:
        await _node.pan123Account(account: account, password: password);
      case CloudDriveType.pan189:
        final ({String msg, bool sms}) r =
            await _node.pan189Account(account: account, password: password);
        if (r.sms) {
          throw CloudDriveLoginException(
            r.msg.isEmpty ? '该账号需短信二次校验（189），请改用验证码登录' : r.msg,
          );
        }
      case CloudDriveType.woniu4k:
        // 对齐 iOS `NodeWoniu4kLoginView.submit`：account + password + verify + taskId。
        await _node.woniuLogin(
          account: account,
          password: password,
          verify: captchaCode,
          taskId: _accountCaptchaTask[type] ?? '',
        );
      default:
        throw CloudDriveLoginException(_unavailableMessage(mode));
    }
    await _recover();
  }

  @override
  String? pendingCaptchaUrl(CloudDriveType type) => _captchaUrl[type];

  @override
  Future<String?> loadAccountCaptcha(CloudDriveType type) async {
    // 仅蜗牛需图形验证码（对齐 iOS `NodeWoniu4kLoginView.fetchVerify`）。
    if (type != CloudDriveType.woniu4k) return null;
    final ({String image, String taskId}) r = await _node.woniuVerify();
    _accountCaptchaTask[type] = r.taskId;
    return r.image;
  }
}

/// 缺省登录网关工厂：按网盘 / 方式路由到已接入实现。
///
/// - 阿里云盘 PG 扫码（`ali` + `pgQr`）→ [AliyunPgLoginGateway]（extscreen 链路，
///   C-盘1；成功后回收 refresh_token 到 `cloud_drive_credentials_v1`）；
/// - 原生扫码（UC / 百度 / 夸克 + `nativeQr`）→ [NativeCloudDriveLoginGateway]
///   （直连官方扫码接口，不经 Node 常驻系统；成功后落 `cloud_drive_credentials_v1`）；
/// - B 站扫码 + Node 托管盘（115/夸克Node/百度Node/UCNode/光鸭/139/迅雷/123/189）
///   → [NodeCloudDriveLoginGateway]（走 Node 常驻系统，成功后由
///   [NodeCredentialSyncService.saveProfile] 回收凭据）；
/// - 其余尚未接线的档位 → [UnavailableCloudDriveLoginGateway]（文案分档对齐 iOS）。
CloudDriveLoginGateway defaultCloudDriveLoginGateway(
  CloudDriveType type,
  CloudDriveLoginMode mode,
) {
  if (AliyunPgLoginGateway.supports(type, mode)) {
    return AliyunPgLoginGateway();
  }
  if (NativeCloudDriveLoginGateway.supports(type, mode)) {
    return NativeCloudDriveLoginGateway();
  }
  if (NodeCloudDriveLoginGateway.supports(type, mode)) {
    return NodeCloudDriveLoginGateway(
      nodeClient: NodeLoginClient(),
      credentialSync: NodeCredentialSyncService(
        client: LocalNodeCredentialApiClient(),
      ),
    );
  }
  return const UnavailableCloudDriveLoginGateway();
}