/// 平台层：Windows 硬件 GPU 探测（dart:ffi 直连 d3d11.dll）。
///
/// media_kit_video 的 `enableHardwareAcceleration: true` 依赖 GPU 渲染
/// （ANGLE/D3D11/EGL）。无真 GPU 的云电脑/远程测试机上，环境变量
/// `SESSIONNAME` 常为 `Console`（非 `rdp`），RDP 启发式无法识别，导致硬解路径
/// EGL 表面创建失败并连带起播崩溃（日志 `Failed to create EGL surface`）。
///
/// 本探测用 `D3D11CreateDevice(D3D_DRIVER_TYPE_HARDWARE)` 直接判断是否存在
/// 硬件 GPU：成功 → 有硬件 GPU；失败（`DXGI_ERROR_UNSUPPORTED` 等）→ 无。
/// 无法探测（非 Windows / d3d11.dll 缺失）时返回 [GpuProbeVerdict.unknown]，
/// 调用方应保守回退软解，避免崩溃。
library;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' show calloc;

/// 硬件 GPU 探测结论。
enum GpuProbeVerdict {
  /// 探测到硬件 GPU（`D3D11CreateDevice` 硬件驱动创建成功）。
  available,

  /// 未探测到硬件 GPU（云电脑 / 无 GPU），应软解。
  unavailable,

  /// 无法探测（非 Windows / d3d11.dll 缺失 / 调用异常），应保守软解。
  unknown,
}

typedef _D3D11CreateDeviceNative = Int32 Function(
    Pointer<Void>, Int32, Pointer<Void>, Uint32, Pointer<Int32>, Uint32, Uint32,
    Pointer<Pointer<Void>>, Pointer<Int32>, Pointer<Pointer<Void>>);
typedef _D3D11CreateDeviceDart = int Function(
    Pointer<Void>, int, Pointer<Void>, int, Pointer<Int32>, int, int,
    Pointer<Pointer<Void>>, Pointer<Int32>, Pointer<Pointer<Void>>);

/// Windows 硬件 GPU 探测（进程内仅执行一次，结果稳定）。
final class HardwareGpuProbe {
  HardwareGpuProbe._();

  static GpuProbeVerdict? _cached;

  /// 探测当前 Windows 机器是否存在硬件加速 GPU。
  static GpuProbeVerdict probe() {
    final GpuProbeVerdict? cached = _cached;
    if (cached != null) return cached;
    final GpuProbeVerdict result = _probeOnce();
    _cached = result;
    return result;
  }

  static GpuProbeVerdict _probeOnce() {
    if (!Platform.isWindows) return GpuProbeVerdict.unknown;
    final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open('d3d11.dll');
    } catch (_) {
      return GpuProbeVerdict.unknown;
    }
    final _D3D11CreateDeviceDart createDevice;
    try {
      createDevice = lib.lookupFunction<_D3D11CreateDeviceNative,
          _D3D11CreateDeviceDart>('D3D11CreateDevice');
    } catch (_) {
      return GpuProbeVerdict.unknown;
    }
    final Pointer<Pointer<Void>> device = calloc<Pointer<Void>>();
    final Pointer<Int32> featureLevel = calloc<Int32>();
    final Pointer<Pointer<Void>> context = calloc<Pointer<Void>>();
    try {
      final int hr = createDevice(
        nullptr, // pAdapter：默认适配器
        1, // D3D_DRIVER_TYPE_HARDWARE
        nullptr, // Software（非 WARP）
        0, // Flags
        nullptr, // pFeatureLevels
        0, // FeatureLevels
        7, // D3D11_SDK_VERSION
        device,
        featureLevel,
        context,
      );
      // 探测成功时 device 持有一个 ID3D11Device COM 引用；此处仅释放指针
      // 外壳。由于结果被缓存、进程内只探测一次，留一个微小的 COM 引用可接受
      // （避免经 vtable 调 IUnknown::Release 引入额外风险）。
      final bool created = hr == 0 && device.value != nullptr;
      return created
          ? GpuProbeVerdict.available
          : GpuProbeVerdict.unavailable;
    } catch (_) {
      return GpuProbeVerdict.unknown;
    } finally {
      calloc.free(device);
      calloc.free(featureLevel);
      calloc.free(context);
    }
  }
}