/// 领域层：六速社区（`lusushequ`，iOS 走 `welfare_spider` + 原生 Service）。
///
/// 唯一真相源：iOS `vbox/Services/LusushequService.swift`。
///
/// **待移植（UI-C1b）**：当前仅保留平台标识 + 域名探测（Fuli-S1 基线）；
/// 内容解析（`/api/old_v3/video/home`，含 `.enc` AES 封面解密 / base64 数据）待补齐。
library;

import 'probed_fuli_service.dart';

/// 六速社区服务（`lusushequ`）。
class LusushequFuliService extends ProbedFuliService {
  /// 构造。
  LusushequFuliService({super.bridge})
      : super(
          platformKey: 'lusushequ',
          platformName: '六速社区',
          defaultHosts: const <String>['https://215.x89cneo.com:51111'],
        );
}
