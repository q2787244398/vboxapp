/// 网盘登录会话控制器（批次 F · F-02）。
///
/// 对齐 iOS 登录态机：
/// - 扫码：`NativeCloudQRLoginView` / `BiliQrLoginView` 的 `qrLoginState`
///   推进（loading → waitingScan → scanned → exchanging → success / error）；
/// - 短信：`NodeGuangyaSMSLoginView` 的 `sendSms` + `loginSms` + 60s 倒计时。
///
/// 协议调用全部经 [CloudDriveLoginGateway]（缺省 [UnavailableCloudDriveLoginGateway]），
/// 使 UI 可脱离后端独立渲染与测试；真实链路由 F-04 / F-05 与 Node 客户端补齐。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/cloud_drive_login.dart';
import 'login_gateway.dart';

/// 网盘登录会话控制器。
class CloudDriveLoginController extends ChangeNotifier {
  /// 构造（[gateway] 可注入替身；缺省为「未接入」网关）。
  CloudDriveLoginController({
    required this.driveType,
    required this.mode,
    CloudDriveLoginGateway gateway = const UnavailableCloudDriveLoginGateway(),
    this.providerOverride,
    this.pollInterval = const Duration(seconds: 2),
    this.smsCooldown = const Duration(seconds: 60),
  }) : _gateway = gateway;

  /// 目标网盘。
  final CloudDriveType driveType;

  /// 登录方式（决定 UI 形态与网关分支）。
  final CloudDriveLoginMode mode;

  /// 覆盖网关默认扫码 provider（UCNode 两步登录第 2 步用 `ucToken`）。
  final String? providerOverride;

  /// 扫码轮询间隔。
  final Duration pollInterval;

  /// 短信验证码冷却时长（对齐 iOS 60s 倒计时）。
  final Duration smsCooldown;

  final CloudDriveLoginGateway _gateway;

  CloudDriveLoginPhase _phase = CloudDriveLoginPhase.idle;
  String _message = '';
  String? _error;
  String? _qrDataUrl;
  String? _taskId;
  int _countdown = 0;
  bool _accountNeedsSms = false;
  Timer? _pollTimer;
  Timer? _cooldownTimer;
  bool _disposed = false;

  /// 当前阶段。
  CloudDriveLoginPhase get phase => _phase;

  /// 状态说明（成功 / 轮询中展示）。
  String get message => _message;

  /// 错误文案（非空时优先于 [message] 展示，对齐 iOS `errorText`）。
  String? get error => _error;

  /// 二维码 data URL（`data:image/png;base64,...` 或裸 base64）。
  String? get qrDataUrl => _qrDataUrl;

  /// 短信验证码冷却剩余秒数。
  int get countdown => _countdown;

  /// 短信冷却是否进行中（按钮置灰）。
  bool get smsCooldownActive => _countdown > 0;

  /// 账号登录是否处于「待短信二次校验」态（天翼 189，对齐 iOS `needSms`）。
  ///
  /// 为 true 时 UI 应展示短信验证码输入并改调 [loginWithAccountSms]。
  bool get accountNeedsSms => _accountNeedsSms;

  /// 主按钮文案（扫码：生成 / 重新生成；短信：验证码登录 / 登录中…）。
  String get primaryLabel {
    if (mode.isSms) {
      return _phase == CloudDriveLoginPhase.loading ? '登录中…' : '验证码登录';
    }
    return _phase.isPolling ? '重新生成二维码' : '生成二维码';
  }

  /// 提示行文案（对齐 iOS `tipCard` 逐档协议说明）。
  String get tipText => switch (mode) {
        CloudDriveLoginMode.nodeSms =>
          '与 Node 常驻系统的验证码登录一致，登录成功后自动回收凭据到授权中心。',
        CloudDriveLoginMode.nodeQr =>
          '使用${driveType.displayName} App 扫码后确认，Cookie 写入 Node 常驻系统'
              '（独立于原生账号，两条路链互不影响）。',
        CloudDriveLoginMode.pgQr =>
          '使用阿里云盘 App 扫描二维码，登录后自动回收 refresh_token（extscreen 链路）。',
        CloudDriveLoginMode.nodeAccount =>
          '与 Node 常驻系统的「账号 + 密码」登录一致，登录成功后自动回收凭据到授权中心。',
        CloudDriveLoginMode.nativeQr ||
        CloudDriveLoginMode.webFallback =>
          '请使用${driveType.displayName} App 扫码并确认，登录成功后自动回收凭据到授权中心。',
      };

  // ─────────────────────────────────────────────────────────
  // 扫码流程
  // ─────────────────────────────────────────────────────────

  /// 生成二维码并发起轮询（对齐 iOS `startLoginFlow` / `startQrLogin`）。
  Future<void> generateQr() async {
    if (_phase.isPolling) return;
    _error = null;
    _qrDataUrl = null;
    _setPhase(CloudDriveLoginPhase.loading, message: '正在生成二维码…');
    try {
      final CloudDriveQrTask task = await _gateway.startQrLogin(
        type: driveType,
        mode: mode,
        providerOverride: providerOverride,
      );
      if (_disposed) return;
      _taskId = task.taskId;
      _qrDataUrl = task.qrDataUrl;
      _setPhase(
        CloudDriveLoginPhase.waitingScan,
        message: '用${driveType.displayName} App 扫描二维码',
      );
      _startPolling();
    } on CloudDriveLoginException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  /// 手动轮询一次（供测试与前台恢复时驱动；定时器内部同样调用）。
  Future<void> pollOnce() async {
    final String? taskId = _taskId;
    if (_disposed || taskId == null || _phase.isTerminal) return;
    try {
      final CloudDriveLoginPhase next = await _gateway.pollQrLogin(
        type: driveType,
        mode: mode,
        taskId: taskId,
        providerOverride: providerOverride,
      );
      if (_disposed || _phase.isTerminal) return;
      if (next == _phase) return;
      _setPhase(next, message: next.displayText);
      if (next.isTerminal) _stopPolling();
    } on CloudDriveLoginException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  /// 取消当前扫码（对齐 iOS `cancel()`：停轮询 + 通知网关 + 回 idle）。
  Future<void> cancel() async {
    _stopPolling();
    final String? taskId = _taskId;
    _taskId = null;
    _qrDataUrl = null;
    _error = null;
    _setPhase(CloudDriveLoginPhase.idle, message: '准备生成二维码');
    if (taskId != null) {
      try {
        await _gateway.cancelQrLogin(taskId);
      } catch (_) {
        // 取消为幂等操作，失败不向上冒泡（对齐 iOS `cancel` 容错）。
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // 短信验证码流程
  // ─────────────────────────────────────────────────────────

  /// 发送短信验证码（对齐 iOS `sendSms`：置冷却 60s）。
  Future<void> sendSms(String phone) async {
    final String trimmed = phone.trim();
    if (trimmed.isEmpty) {
      _error = '请输入手机号';
      _safeNotify();
      return;
    }
    _error = null;
    _setPhase(CloudDriveLoginPhase.loading, message: '正在发送验证码…');
    try {
      final String taskId = await _gateway.sendSmsCode(
        type: driveType,
        phone: trimmed,
      );
      if (_disposed) return;
      _taskId = taskId;
      _setPhase(CloudDriveLoginPhase.waitingScan, message: '验证码已发送');
      _startCooldown();
    } on CloudDriveLoginException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  /// 提交短信验证码完成登录（对齐 iOS `loginSms`）。
  Future<void> loginWithSms(String code) async {
    final String trimmed = code.trim();
    final String? taskId = _taskId;
    if (taskId == null || taskId.isEmpty) {
      _error = '请先获取验证码';
      _safeNotify();
      return;
    }
    if (trimmed.isEmpty) {
      _error = '请输入短信验证码';
      _safeNotify();
      return;
    }
    _error = null;
    _setPhase(CloudDriveLoginPhase.loading, message: '正在登录…');
    try {
      await _gateway.submitSmsCode(
        type: driveType,
        taskId: taskId,
        code: trimmed,
      );
      if (_disposed) return;
      _setPhase(CloudDriveLoginPhase.success, message: '登录成功');
    } on CloudDriveLoginException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // 账号密码流程
  // ─────────────────────────────────────────────────────────

  /// 账号密码登录（对齐 iOS `NodePan123LoginView` / `NodeWoniu4kLoginView`）。
  ///
  /// [captchaCode] 为图形验证码（蜗牛 `woniu4k` 需要；其余留空）。
  ///
  /// 对齐 iOS `NodePan189AccountLoginView.submit`：若网关返回 `needSms == true`
  /// （天翼 189 二次校验），进入 [accountNeedsSms] 态（未登录成功），
  /// 由 UI 追加验证码后调用 [loginWithAccountSms]。
  Future<void> loginWithAccount(
    String account,
    String password, {
    String captchaCode = '',
  }) async {
    final String user = account.trim();
    if (user.isEmpty) {
      _error = '请输入账号';
      _safeNotify();
      return;
    }
    if (password.isEmpty) {
      _error = '请输入密码';
      _safeNotify();
      return;
    }
    _error = null;
    _setPhase(CloudDriveLoginPhase.loading, message: '正在登录…');
    try {
      final CloudDriveAccountResult result = await _gateway.submitAccountLogin(
        type: driveType,
        mode: mode,
        account: user,
        password: password,
        captchaCode: captchaCode,
      );
      if (_disposed) return;
      _accountNeedsSms = result.needSms;
      if (result.needSms) {
        _setPhase(
          CloudDriveLoginPhase.idle,
          message: result.message.isEmpty ? '请输入短信验证码' : result.message,
        );
      } else {
        _setPhase(CloudDriveLoginPhase.success, message: '登录成功');
      }
    } on CloudDriveLoginException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  /// 账号登录的短信二次校验（对齐 iOS 天翼 189 的 `needSms` 分支）。
  Future<void> loginWithAccountSms(String code) async {
    final String trimmed = code.trim();
    if (trimmed.isEmpty) {
      _error = '请输入短信验证码';
      _safeNotify();
      return;
    }
    _error = null;
    _setPhase(CloudDriveLoginPhase.loading, message: '正在验证短信…');
    try {
      await _gateway.submitAccountSmsCode(type: driveType, code: trimmed);
      if (_disposed) return;
      _accountNeedsSms = false;
      _setPhase(CloudDriveLoginPhase.success, message: '登录成功');
    } on CloudDriveLoginException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // 内部
  // ─────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => pollOnce());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _countdown = smsCooldown.inSeconds;
    _safeNotify();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      if (_countdown > 1) {
        _countdown -= 1;
      } else {
        _countdown = 0;
        timer.cancel();
        _cooldownTimer = null;
      }
      _safeNotify();
    });
  }

  void _setPhase(CloudDriveLoginPhase phase, {required String message}) {
    _phase = phase;
    _message = message;
    _safeNotify();
  }

  void _fail(String message) {
    _stopPolling();
    _error = message;
    _phase = CloudDriveLoginPhase.failed;
    _message = CloudDriveLoginPhase.failed.displayText;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    super.dispose();
  }
}
