/// 领域层：熊猫视频（`panda_video`，POST API 类）。
///
/// 唯一真相源：iOS `vbox/Services/PandaVideoService.swift`。
///
/// **待移植（UI-C1b）**：当前仅保留平台标识 + 域名探测（Fuli-S1 基线）；
/// 内容解析（`/getDataInit` / `/forward` POST API）待补齐。
library;

import 'probed_fuli_service.dart';

/// 熊猫视频服务（`panda_video`）。
class PandaFuliService extends ProbedFuliService {
  /// 构造。
  PandaFuliService({super.bridge})
      : super(
          platformKey: 'panda_video',
          platformName: '熊猫视频',
          defaultHosts: const <String>[
            'https://spiderscloudcn2.51111666.com',
            'https://spiderscloudcn1.51111666.com',
          ],
        );
}
