/// 平台层：QuickJS 原生 FFI 绑定抽象（G-03-B-1）。
///
/// 对应原生侧：`quickjs/wrapper.c`（纯 C，三端可编译，产物 `libvbox_quickjs`）。
/// Dart 侧经 `dart:ffi` 加载动态库并调用 `vq_*` 符号，语义对齐 iOS
/// `vbox/Libraries/QuickJSBridge.m` + `QJSSpiderEngine.evaluateJS`：
/// - `eval` 返回 JS 表达式求值结果的字符串（异常时返回 Error 前缀消息）
/// - 返回值由原生库持有，Dart 复制后由实现内部调用 `vq_free_string` 释放
///
/// 设计：`QuickJsNativeBridge` 抽象可注入 —— 单测使用 fake 实现（FFI mock），
/// 运行环境使用 [DartFfiQuickJsBridge]（加载失败时 `isAvailable == false`）。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 按平台解析动态库名（Android / Linux 用 .so，macOS .dylib，Windows .dll）。
String quickJsLibraryName() => switch (Platform.operatingSystem) {
      'macos' => 'libvbox_quickjs.dylib',
      'windows' => 'vbox_quickjs.dll',
      _ => 'libvbox_quickjs.so',
    };

/// QuickJS 原生桥接口（FFI mock 与真实实现共用）。
abstract class QuickJsNativeBridge {
  /// 原生库是否已成功加载（false 时调用方应回退 / 抛错）。
  bool get isAvailable;

  /// 创建运行时，返回不透明句柄（原生指针地址；失败返回 0）。
  int createRuntime();

  /// 在 [runtime] 上创建上下文（含 console/print 注册），失败返回 0。
  int createContext(int runtime);

  /// 释放上下文（必须先于 runtime，对齐 iOS 清理顺序）。
  void freeContext(int context);

  /// 释放运行时（内部先 JS_RunGC）。
  void freeRuntime(int runtime);

  /// 执行脚本并返回结果字符串；异常时返回 `Error/TypeError/...` 前缀消息。
  String? eval(int context, String script);
}

/// `dart:ffi` 实现：加载 `libvbox_quickjs` 动态库。
class DartFfiQuickJsBridge implements QuickJsNativeBridge {
  DartFfiQuickJsBridge({String? libraryName}) {
    try {
      _lib = DynamicLibrary.open(libraryName ?? quickJsLibraryName());
    } on ArgumentError {
      // 库不存在（本机未打包 / 测试环境）→ isAvailable == false
      _lib = null;
    }
  }

  DynamicLibrary? _lib;

  late final Pointer<Void> Function() _createRuntime =
      _lookup('vq_create_runtime');
  late final Pointer<Void> Function(Pointer<Void>) _createContext =
      _lookup('vq_create_context');
  late final void Function(Pointer<Void>) _freeRuntime = _lookup('vq_free_runtime');
  late final void Function(Pointer<Void>) _freeContext = _lookup('vq_free_context');
  late final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>) _eval =
      _lookup('vq_eval');
  late final void Function(Pointer<Void>, Pointer<Utf8>) _freeString =
      _lookup('vq_free_string');

  T _lookup<T>(String name) {
    final DynamicLibrary lib = _lib!;
    return lib.lookupFunction<NativeFunction<T>, T>(name);
  }

  @override
  bool get isAvailable => _lib != null;

  @override
  int createRuntime() {
    final Pointer<Void> p = _createRuntime();
    return p.address;
  }

  @override
  int createContext(int runtime) {
    final Pointer<Void> p = _createContext(Pointer<Void>.fromAddress(runtime));
    return p.address;
  }

  @override
  void freeContext(int context) {
    if (context != 0) {
      _freeContext(Pointer<Void>.fromAddress(context));
    }
  }

  @override
  void freeRuntime(int runtime) {
    if (runtime != 0) {
      _freeRuntime(Pointer<Void>.fromAddress(runtime));
    }
  }

  @override
  String? eval(int context, String script) {
    if (context == 0) return null;
    final Pointer<Utf8> scriptPtr = script.toNativeUtf8();
    final Pointer<Void> ctxPtr = Pointer<Void>.fromAddress(context);
    final Pointer<Utf8> resultPtr = _eval(ctxPtr, scriptPtr);
    malloc.free(scriptPtr); // toNativeUtf8 默认用 malloc 分配，立即释放
    if (resultPtr == nullptr) return null;
    final String result = resultPtr.toDartString();
    _freeString(ctxPtr, resultPtr); // 原生侧 JS_FreeCString
    return result;
  }
}

/// 原生库不可用时的桥（`isAvailable == false`，所有调用为安全 no-op）。
///
/// 引擎在 `isAvailable == false` 时抛 `SpiderException(unimplemented)`，
/// 使未打包原生库的环境（CI 单测 / 开发机）可安全降级。
class UnavailableQuickJsBridge implements QuickJsNativeBridge {
  const UnavailableQuickJsBridge();

  @override
  bool get isAvailable => false;

  @override
  int createRuntime() => 0;

  @override
  int createContext(int runtime) => 0;

  @override
  void freeContext(int context) {}

  @override
  void freeRuntime(int runtime) {}

  @override
  String? eval(int context, String script) => null;
}
