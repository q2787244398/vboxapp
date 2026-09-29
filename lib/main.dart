/// VBox 应用入口。
///
/// 方案 D5：三端全平台并行（Android 手机 / Android TV / Windows / macOS / iOS 维持）。
/// 方案 D6：播放器策略 —— Android Media3+libVLC；桌面 libmpv。
///
/// 本文件仅负责：
///  1. 绑定 Flutter 引擎
///  2. 桌面端 sqflite FFI 初始化
///  3. 启动 [VBoxApp]
///
/// ⚠️ iOS 不迁移（D1），Flutter 仅负责 Android / TV / Windows / macOS 四端。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端（Windows / macOS / Linux）需初始化 sqflite FFI 后端
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const VBoxApp());
}
