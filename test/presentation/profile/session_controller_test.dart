/// 呈现层单测：本地账号会话控制器（批次 I · I-02）。
///
/// 唯一真相源：iOS `ProfileView.swift`
///   · L808-L839（`performLogout` / `loadInitialState`）；
///   · L1072-L1125（`isRegistered` / `performLogin` / `loginSuccess`）。
///
/// 落盘以 [InMemorySettingsStore] 替代 SQLite `settings` 表（隔离 IO）；
/// 登录延迟置 `Duration.zero`，避免用例受节拍影响。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/presentation/profile/session_controller.dart';

import '../../support/fakes.dart';

/// 构造一个零延迟控制器（共享同一内存 store 便于跨实例断言持久化）。
SessionController _controller(InMemorySettingsStore store) =>
    SessionController(store: store, loginDelay: Duration.zero);

void main() {
  group('初始态与 load', () {
    test('全新设备：未登录 · 展示名「未登录」', () async {
      final SessionController c = _controller(InMemorySettingsStore());
      await c.load();
      expect(c.isLoggedIn, isFalse);
      expect(c.account, isEmpty);
      expect(c.username, isEmpty);
      expect(c.avatarBase64, isNull);
      expect(c.displayName, '未登录');
    });

    test('load：从落盘键还原登录态 / 账号 / 展示名 / 头像', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.kAccountKey: '199114',
        SessionController.kUsernameKey: 'vbox 默认账号',
        SessionController.kLoggedInKey: 'true',
        SessionController.kAvatarKey: 'AAAA',
      });
      final SessionController c = _controller(store);
      await c.load();
      expect(c.isLoggedIn, isTrue);
      expect(c.account, '199114');
      expect(c.username, 'vbox 默认账号');
      expect(c.avatarBase64, 'AAAA');
      // 展示名优先取可改的 username。
      expect(c.displayName, 'vbox 默认账号');
    });

    test('load：account 为空 → 用旧 username 兜底迁移（对齐 iOS L827）', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.kAccountKey: '',
        SessionController.kUsernameKey: '老账号',
        SessionController.kLoggedInKey: 'true',
      });
      final SessionController c = _controller(store);
      await c.load();
      expect(c.account, '老账号');
      expect(c.username, '老账号');
      expect(c.displayName, '老账号');
    });

    test('load：isLoggedIn 非 "true" 一律视为未登录', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.kAccountKey: '199114',
        SessionController.kLoggedInKey: 'false',
      });
      final SessionController c = _controller(store);
      await c.load();
      expect(c.isLoggedIn, isFalse);
      expect(c.displayName, '未登录');
    });
  });

  group('isRegistered / login', () {
    test('isRegistered：无密码键 → false；有非空密码键 → true', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.passwordKey('registered'): 'pwd',
      });
      final SessionController c = _controller(store);
      expect(await c.isRegistered('registered'), isTrue);
      expect(await c.isRegistered('newbie'), isFalse);
      expect(await c.isRegistered('   '), isFalse);
    });

    test('login：首次登录即注册 —— 写入 password_<账号> 并落库登录态', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SessionController c = _controller(store);

      final String? error = await c.login(account: '199114', password: 'abc');
      expect(error, isNull);
      expect(c.isLoggedIn, isTrue);
      expect(c.account, '199114');
      expect(c.username, '199114');
      expect(c.displayName, '199114');
      expect(store.snapshot[SessionController.passwordKey('199114')], 'abc');
      expect(store.snapshot[SessionController.kLoggedInKey], 'true');
      expect(store.snapshot[SessionController.kAccountKey], '199114');
    });

    test('login：账号 / 密码去空格（对齐 iOS trimmed）', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SessionController c = _controller(store);
      expect(await c.login(account: '  199114 ', password: ' abc '), isNull);
      expect(c.account, '199114');
      expect(store.snapshot[SessionController.passwordKey('199114')], 'abc');
    });

    test('login：空账号 / 空密码 → 返回文案且不改变登录态', () async {
      final SessionController c = _controller(InMemorySettingsStore());
      expect(await c.login(account: '', password: 'abc'), '请输入用户名');
      expect(await c.login(account: '199114', password: '   '), '请输入密码');
      expect(c.isLoggedIn, isFalse);
    });

    test('login：已注册 + 密码错误 → 「密码错误，请重试」，仍为未登录', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.passwordKey('199114'): 'right',
      });
      final SessionController c = _controller(store);
      final String? error =
          await c.login(account: '199114', password: 'wrong');
      expect(error, '密码错误，请重试');
      expect(c.isLoggedIn, isFalse);
      expect(c.loading, isFalse);
    });

    test('login：已注册 + 密码正确 → 登录成功', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.passwordKey('199114'): 'right',
      });
      final SessionController c = _controller(store);
      expect(await c.login(account: '199114', password: 'right'), isNull);
      expect(c.isLoggedIn, isTrue);
      expect(c.account, '199114');
    });

    test('login：已注册且已有展示名 → 保留展示名（账号与用户名分离）', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.kUsernameKey: 'vbox 默认账号',
        SessionController.passwordKey('199114'): 'right',
      });
      final SessionController c = _controller(store);
      await c.load();
      expect(await c.login(account: '199114', password: 'right'), isNull);
      expect(c.account, '199114');
      expect(c.username, 'vbox 默认账号');
      expect(c.displayName, 'vbox 默认账号');
    });
  });

  group('logout / rename', () {
    test('logout：清除登录态，但保留 password_<账号> 与头像（对齐 iOS 文案）', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SessionController.kAvatarKey: 'AAAA',
      });
      final SessionController c = _controller(store);
      await c.login(account: '199114', password: 'abc');

      await c.logout();
      expect(c.isLoggedIn, isFalse);
      expect(c.account, isEmpty);
      expect(c.username, isEmpty);
      expect(c.displayName, '未登录');
      expect(store.snapshot[SessionController.kLoggedInKey], 'false');
      // 密码与头像保留 —— 再次登录仍可用旧密码。
      expect(store.snapshot[SessionController.passwordKey('199114')], 'abc');
      expect(store.snapshot[SessionController.kAvatarKey], 'AAAA');
      expect(await c.login(account: '199114', password: 'abc'), isNull);
    });

    test('rename：改展示名不改登录账号，并持久化 username', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SessionController c = _controller(store);
      await c.login(account: '199114', password: 'abc');

      await c.rename('vbox 默认账号');
      expect(c.username, 'vbox 默认账号');
      expect(c.account, '199114');
      expect(c.displayName, 'vbox 默认账号');
      expect(store.snapshot[SessionController.kUsernameKey], 'vbox 默认账号');
      expect(store.snapshot[SessionController.kAccountKey], '199114');
    });

    test('rename：空名或同名 → 忽略（不落库）', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SessionController c = _controller(store);
      await c.login(account: '199114', password: 'abc');

      await c.rename('   ');
      expect(c.username, '199114');
      await c.rename('199114');
      expect(c.username, '199114');
    });
  });
}