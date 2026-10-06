/// 领域层：香蕉视频（`banana_video`，HTML 类）。
///
/// 唯一真相源：iOS `vbox/Services/BananaVideoService.swift`。
///
/// **待移植（UI-C1b）**：当前仅保留平台标识 + 域名探测（Fuli-S1 基线）；
/// 内容解析（`/index.php/vod/type/id/...` HTML，含 `domain_id` 拆域名）待补齐。
library;

import 'probed_fuli_service.dart';

/// 香蕉视频服务（`banana_video`）。
class BananaFuliService extends ProbedFuliService {
  /// 构造。
  BananaFuliService({super.bridge})
      : super(
          platformKey: 'banana_video',
          platformName: '香蕉视频',
          defaultHosts: const <String>[
            'https://618013.xyz',
            'https://618012.xyz',
            'https://618011.xyz',
            'https://618010.xyz',
            'https://618009.xyz',
          ],
        );
}
