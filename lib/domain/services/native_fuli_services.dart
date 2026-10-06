/// 领域层：原生福利平台服务注册（批次 H · Fuli-S1 / UI-C1b）。
///
/// 唯一真相源：iOS `vbox/WelfareRemote/WelfarePlatformRouter.swift`
///   · `makeFuliBaseDestination`（L160-L184）注册 4 个 `fuli_base` key：
///     `panda_video` / `four_h_video` / `full_hd` / `banana_video`；
///   · `aidan_video` → `AidanVideoService`（L123-L126）；
///   · `welfare_spider` + `lusushequ` → 原生 `LusushequService`（L196-L209）。
///
/// UI-C1b 批次起，各平台解析实现拆为「一服务一文件」（对齐 iOS 组织）：
///   · [ProbedFuliService] 基类 → `probed_fuli_service.dart`；
///   · 各平台服务 → 同名 `*_service.dart`；
///   · 本文件仅保留注册入口，并 `export` 以上文件以维持既有 import 兼容。
library;

import '../../platform/spider/spider_http_bridge.dart';
import 'aidan_video_service.dart';
import 'banana_video_service.dart';
import 'four_h_video_service.dart';
import 'fuli_base_service.dart';
import 'full_hd_service.dart';
import 'lusushequ_service.dart';
import 'panda_video_service.dart';
import 'probed_fuli_service.dart';

export 'aidan_video_service.dart';
export 'banana_video_service.dart';
export 'four_h_video_service.dart';
export 'full_hd_service.dart';
export 'lusushequ_service.dart';
export 'panda_video_service.dart';
export 'probed_fuli_service.dart';

/// 注册原生福利平台服务（应用装配时调用；对齐 iOS 各 `*Service.shared` 的接线）。
///
/// [registry] / [bridge] 供测试注入。
void registerNativeFuliServices({
  FuliBaseServiceRegistry? registry,
  SpiderHttpBridge? bridge,
}) {
  final FuliBaseServiceRegistry target =
      registry ?? FuliBaseServiceRegistry.shared;
  // fuli_base（iOS makeFuliBaseDestination 的 4 个 key）。
  target.register(PandaFuliService(bridge: bridge));
  target.register(FourHFuliService(bridge: bridge));
  target.register(FullHDFuliService(bridge: bridge));
  target.register(BananaFuliService(bridge: bridge));
  // aidan_video / lusushequ（iOS 走各自路由，服务同源注册）。
  target.register(AidanFuliService(bridge: bridge));
  target.register(LusushequFuliService(bridge: bridge));
}
