/// 领域层：4H 视频（`four_h_video`，HTML 类）。
///
/// 唯一真相源：iOS `vbox/Services/FourHVideoService.swift`。
///
/// **待移植（UI-C1b）**：当前仅保留平台标识 + 域名探测（Fuli-S1 基线）；
/// 内容解析（`/vod/type/id/{tid}/page/{pg}.html` HTML + XPath）待补齐。
library;

import 'probed_fuli_service.dart';

/// 4H 视频服务（`four_h_video`）。
class FourHFuliService extends ProbedFuliService {
  /// 构造。
  FourHFuliService({super.bridge})
      : super(
          platformKey: 'four_h_video',
          platformName: '4H视频',
          defaultHosts: const <String>[
            'https://4h05.cc',
            'https://4h04.cc',
            'https://4h03.cc',
          ],
        );
}
