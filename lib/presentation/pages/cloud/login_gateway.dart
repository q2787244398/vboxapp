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
typedef CloudDriveQrTask = ({String taskId, String qrDataUrl});

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
}
