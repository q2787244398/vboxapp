/// 网盘登录网关（批次 F · F-02 接缝）。
///
/// 把「原生扫码 / Node 扫码 / Node 短信验证码 / Node 账号 / 网页兜底」的**协议
/// 调用**抽象为接口，UI 与状态机（`login_controller.dart`）只依赖本抽象：
/// - 真实实现随 F-04（阿里 extscreen 链）、F-05（B站扫码 + 百度专用代理）与
///   Node 常驻系统 HTTP 客户端补齐；
/// - 本段提供 [UnavailableCloudDriveLoginGateway] 作为缺省实现，行为对齐 iOS
///   —— Node 未就绪时 `NodeLoginAPIClient.request` 抛 `nodeNotReady`，页面显示
///   「Node 常驻系统未就绪」（`NodeLoginViews.swift:22`）。
library;

import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/cloud_drive_login.dart';

/// 扫码任务句柄（Node/原生协议返回 `taskId` + 二维码 data URL）。
///
/// `qrDataUrl` 两种形态：
/// - 图片 data URL（`data:image/png;base64,...` 或裸 base64）→ 直接渲染图片；
/// - **`qr_data:<文本>`** 前缀 → 文本为待编码的授权链接，由表现层本地生成二维码
///   （C-盘3：PG/extscreen 返回链接而非图片）。
typedef CloudDriveQrTask = ({String taskId, String qrDataUrl});

/// `qrDataUrl` 承载「待编码文本」的前缀（见 [CloudDriveQrTask]）。
const String kQrDataContentPrefix = 'qr_data:';

/// 取 [CloudDriveQrTask.qrDataUrl] 中的待编码文本（非该形态返回 null）。
String? qrContentOf(String? qrDataUrl) {
  if (qrDataUrl == null) return null;
  if (!qrDataUrl.startsWith(kQrDataContentPrefix)) return null;
  final String content = qrDataUrl.substring(kQrDataContentPrefix.length);
  return content.isEmpty ? null : content;
}

/// 登录网关错误（文案对齐 iOS `NodeLoginError`）。
class CloudDriveLoginException implements Exception {
  /// 构造。
  const CloudDriveLoginException(this.message);

  /// 面向用户的错误文案。
  final String message;

  @override
  String toString() => message;
}

/// 网盘登录网关抽象。
///
/// 所有方法失败时抛 [CloudDriveLoginException]（UI 统一渲染到错误行）。
abstract interface class CloudDriveLoginGateway {
  /// 发起扫码：返回任务句柄（[CloudDriveQrTask]）。
  Future<CloudDriveQrTask> startQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
  });

  /// 轮询一次扫码任务：返回下一刻阶段。
  ///
  /// 阶段推进：`waitingScan → scanned → exchanging → success`；终端态即停轮询。
  Future<CloudDriveLoginPhase> pollQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String taskId,
  });

  /// 取消扫码任务（幂等；失败不抛）。
  Future<void> cancelQrLogin(String taskId);

  /// 发送短信验证码：返回 Node 侧 `taskId`。
  Future<String> sendSmsCode({
    required CloudDriveType type,
    required String phone,
  });

  /// 提交短信验证码完成登录（成功后由实现侧回收凭据）。
  Future<void> submitSmsCode({
    required CloudDriveType type,
    required String taskId,
    required String code,
  });

  /// 短信登录过程中若需滑块验证，返回验证码页面地址（对齐 iOS 139 `captchaUrl`）。
  ///
  /// 供 UI 在短信 Sheet 内嵌 WebView 过滑块（Web-R3）；无则返回 null。
  String? pendingCaptchaUrl(CloudDriveType type);

  /// 账号密码登录（Node 托管盘：123 / 蜗牛 / 天翼 等）。
  ///
  /// 对齐 iOS `NodePan123LoginView` / `NodeWoniu4kLoginView` 的
  /// `PUT /website/api/pan123/account {account, password}` 语义，
  /// 成功后由实现侧回收凭据并同步到本机安全存储。
  Future<void> submitAccountLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String account,
    required String password,
  });
}

/// 缺省网关：登录链尚未接入，统一抛「未就绪」。
///
/// 文案分档对齐 iOS —— Node 托管档报「Node 常驻系统未就绪」，原生档报
/// 「原生登录链路尚未接入」（F-04 / F-05 落地）。
class UnavailableCloudDriveLoginGateway implements CloudDriveLoginGateway {
  /// 构造。
  const UnavailableCloudDriveLoginGateway();

  String _messageFor(CloudDriveLoginMode mode) =>
      mode.usesNode ? 'Node 常驻系统未就绪' : '原生登录链路尚未接入';

  @override
  Future<CloudDriveQrTask> startQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
  }) async =>
      throw CloudDriveLoginException(_messageFor(mode));

  @override
  Future<CloudDriveLoginPhase> pollQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String taskId,
  }) async =>
      throw CloudDriveLoginException(_messageFor(mode));

  @override
  Future<void> cancelQrLogin(String taskId) async {}

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

  @override
  String? pendingCaptchaUrl(CloudDriveType type) => null;
}
