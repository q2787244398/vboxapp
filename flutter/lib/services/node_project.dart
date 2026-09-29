import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// 把 Node 引擎的 JS 工程从 Flutter assets 铺到应用可写目录，并完成模板占位符替换。
///
/// 为什么放在 Dart 侧：
///   `node-main-template.js` 的注释写明 ——
///   "Runtime values are injected by NodeService before native launch."
///   即占位符替换本来就应该由 Dart 完成，原生侧只负责设环境变量并执行 node。
///   这样 Android / iOS 的原生桥都能保持极薄，且逻辑只有一份。
///
/// 目录布局（`<docs>/nodejs-project/`）：
///   node-main-template.js   入口（占位符已替换）
///   node-intl-polyfill.js   Intl 兜底（nodejs-mobile 以 --with-intl=none 构建）
///   <bundle>.js             由 config 指定，默认 catpaw_index.js
class NodeProject {
  NodeProject._();

  static const int defaultPort = 9775;
  static const int defaultDartPort = 9776;

  /// iOS 上 nodejs-mobile 的 V8 **无法启用 JIT**（官方 BUILDING.md 明确
  /// "v8 engine configured to start with JIT disabled"），因此 bundle 的解析
  /// 完全靠解释执行。实测同一台 arm64 设备：
  ///     catpaw_index.js (5.6MB) -> 约 23 秒
  ///     kstore_index.js (6.2MB) -> 约 68 秒
  /// 体积接近但差 3 倍，说明耗时取决于代码结构而非体积。故默认选 catpaw。
  static const String defaultBundle = 'catpaw_index.js';

  static const List<String> _jsAssets = <String>[
    'assets/js/node-main-template.js',
    'assets/js/node-intl-polyfill.js',
  ];

  static const List<String> _nodeAssets = <String>[
    'assets/node/catpaw_index.js',
    'assets/node/kstore_index.js',
  ];

  /// 铺好 JS 工程并返回其绝对路径。可重复调用（幂等）。
  ///
  /// [bundle] 为 bundle 文件名，需存在于 `assets/node/` 下。
  static Future<String> stage({
    String bundle = defaultBundle,
    int port = defaultPort,
    int dartPort = defaultDartPort,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/nodejs-project');
    await dir.create(recursive: true);

    // 小文件每次都覆盖：成本极低，且能保证版本升级后立即生效。
    for (final String asset in _jsAssets) {
      final String name = asset.split('/').last;
      final Uint8List data = await _load(asset);
      await File('${dir.path}/$name').writeAsBytes(data, flush: true);
    }

    // bundle 较大（5~6MB），只在缺失或大小变化时重写，避免每次启动都产生写放大。
    for (final String asset in _nodeAssets) {
      final String name = asset.split('/').last;
      final File target = File('${dir.path}/$name');
      final ByteData probe = await rootBundle.load(asset);
      if (await target.exists() && await target.length() == probe.lengthInBytes) {
        continue;
      }
      await target.writeAsBytes(
        probe.buffer.asUint8List(probe.offsetInBytes, probe.lengthInBytes),
        flush: true,
      );
    }

    // 占位符替换：Dart 侧负责，原生侧不再做任何文本处理。
    //
    // BUNDLE_PATH 必须是**可解析的路径**而非裸模块名：模板里是
    //     const resolvedBundlePath = require.resolve(bundlePath);
    // 没有传 paths 选项，裸名会去 node_modules 找而报 Cannot find module。
    final File bundleFile = File('${dir.path}/$bundle');
    if (!await bundleFile.exists()) {
      throw StateError('bundle 不存在: ${bundleFile.path}');
    }
    final File template = File('${dir.path}/node-main-template.js');
    String source = await template.readAsString();
    source = source
        .replaceAll('__TVS_PORT__', '$port')
        .replaceAll('__TVS_DART_PORT__', '$dartPort')
        .replaceAll('__TVS_BUNDLE_PATH__', _jsString(bundleFile.path))
        .replaceAll('__TVS_NODE_DIR__', _jsString(dir.path));
    if (source.contains('__TVS_')) {
      throw StateError('模板中仍有未替换的占位符，bundle/nodeDir 可能包含异常字符');
    }
    await template.writeAsString(source, flush: true);

    // 首次启动时引擎需要一份 db.json；缺失时才写默认值，避免覆盖用户配置。
    final File db = File('${dir.path}/db.json');
    if (!await db.exists()) {
      await db.writeAsString(
        jsonEncode(<String, dynamic>{
          'pans': <String, dynamic>{'list': <dynamic>[]},
          'sites': <String, dynamic>{'list': <dynamic>[]},
          'flags': <dynamic>[],
        }),
        flush: true,
      );
    }

    return dir.path;
  }

  /// 把字符串安全地嵌入 JS 单引号字面量。
  static String _jsString(String value) {
    final String escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }

  static Future<Uint8List> _load(String asset) async {
    final ByteData data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
