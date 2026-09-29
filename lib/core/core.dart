/// 核心层 barrel（通用能力：常量 / 错误 / 网络 / 存储 / 工具）。
///
/// 依赖方向：`presentation → domain → data → core`（core 不反向依赖任何层）。
library;

export 'constants/constants.dart';
export 'errors/errors.dart';
export 'network/network.dart';
export 'storage/storage.dart';
export 'utils/utils.dart';
