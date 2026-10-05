/// 表现层单测：蜗牛账号登录的图形验证码（对齐 iOS `NodeWoniu4kLoginView`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/cloud/cloud_drive.dart';
import 'package:vbox/presentation/pages/cloud/login_gateway.dart';
import 'package:vbox/presentation/pages/cloud/login_sheet.dart';

/// 1×1 PNG data URL（测试可解码）。
const String _onePixelPng =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

/// 提供图形验证码的网关（其余继承「未接入」实现）。
class _WoniuGateway extends UnavailableCloudDriveLoginGateway {
  const _WoniuGateway();

  @override
  Future<String?> loadAccountCaptcha(CloudDriveType type) async => _onePixelPng;
}

void main() {
  testWidgets('蜗牛：进入账号 Sheet 自动展示图形验证码输入框', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CloudDriveAccountLoginSheet(
            driveType: CloudDriveType.woniu4k,
            gateway: _WoniuGateway(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('cloud_login_verify')),
      findsOneWidget,
    );
  });

  testWidgets('无图形验证码的盘：不展示验证码输入框', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CloudDriveAccountLoginSheet(driveType: CloudDriveType.pan123),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('cloud_login_verify')),
      findsNothing,
    );
  });
}