/// 领域层：FullHD（`full_hd`，HTML 类）。
///
/// 唯一真相源：iOS `vbox/Services/FullHDService.swift`。
///
/// **待移植（UI-C1b）**：当前仅保留平台标识 + 域名探测（Fuli-S1 基线）；
/// 内容解析（`/zh/` `/zh/{cid}/` HTML）待补齐。
library;

import 'probed_fuli_service.dart';

/// FullHD 服务（`full_hd`）。
class FullHDFuliService extends ProbedFuliService {
  /// 构造。
  FullHDFuliService({super.bridge})
      : super(
          platformKey: 'full_hd',
          platformName: 'FullHD',
          defaultHosts: const <String>[
            'https://www.fullhd.xxx',
            'https://fullhd.xxx',
          ],
        );
}
