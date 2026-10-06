//
//  PlayerPlugin.swift
//  Runner
//
//  macOS 播放器插件（AVPlayer 主后端 + Wave G · R-渲3 libmpv 复杂封装回退后端）。
//
//  对齐契约 §2.5 播放器能力矩阵 + A21.5 回退策略 + iOS `PlayerEngine` 协议（type/state/event）：
//    · MethodChannel `com.vbox.player/player`：open / play / pause / seekTo / setVolume / setSpeed / dispose
//    · EventChannel `com.vbox.player/player/events`：state / progress / videoSize / error
//  与 Android `PlayerPlugin.kt` / Windows `player_plugin.cpp` 共用同一 wire 协议
//  （Dart `ChannelPlayer._onEvent` 解析面）。
//
//  后端口径：
//    · 常规封装（mp4 / m3u8 / flv 软解 …）→ AVPlayer（主后端，原生硬解 / VideoToolbox）；
//    · 复杂封装（MKV / FLV / TS / RMVB / AVI / WMV / M2TS）→ libmpv 回退（R-渲3），
//      对齐 Android「复杂封装投 libVLC」口径；libmpv 不可用（D28 分发缺失）时上报
//      `E_BACKEND_UNAVAILABLE` 由 Dart `PlayerController` 处理。
//
//  libmpv 运行时（D28）：`libmpv.dylib` + 同组依赖 dylib 随 App `Contents/Frameworks`
//  分发（CI `build-release-assets.yml` 注入），运行期 `dlopen` 动态解析符号，构建期
//  不依赖第三方导入库（对齐 Windows `player_plugin.cpp` 的 `LoadLibraryW` 模式，故
//  无需改 Xcode 链接配置）。
//
//  渲染口径（R-渲1）：`vo=libmpv` + `mpv_render_context`（`MPV_RENDER_API_TYPE_SW`）
//  把每帧软渲染为 BGRA，装入 `CVPixelBuffer` 经 FlutterTexture 上屏；`open` 返回
//  `textureId` 交 Dart `Texture(textureId:)` 承载（UI 层与 iOS 一致，无 PlatformView）。
//

import AVFoundation
import CoreVideo
import Darwin
import FlutterMacOS
import Foundation
import QuartzCore

// ═══════════════ Wave G · R-渲3：libmpv C ABI（dlopen/dlsym 运行期解析）═══════════════
//
// `libmpv/client.h` / `render.h` 未随仓库分发（macOS Runner 无桥接头），此处按 mpv ABI
// 在 Swift 侧等值声明本插件用到的结构 / 枚举 / 函数指针子集；布局与官方头一一对应，
// 不得改动。枚举值见 mpv 官方 client.h / render.h。

private let mpvFormatFlag: Int32 = 3      // MPV_FORMAT_FLAG
private let mpvFormatInt64: Int32 = 4     // MPV_FORMAT_INT64
private let mpvFormatDouble: Int32 = 5    // MPV_FORMAT_DOUBLE

private let mpvEventShutdown: Int32 = 1
private let mpvEventStartFile: Int32 = 6
private let mpvEventEndFile: Int32 = 7
private let mpvEventFileLoaded: Int32 = 8
private let mpvEventPlaybackRestart: Int32 = 21
private let mpvEventPropertyChange: Int32 = 22

private let mpvEndFileReasonEOF: Int32 = 0
private let mpvEndFileReasonError: Int32 = 4

private let mpvRenderParamAPIType: Int32 = 1
private let mpvRenderParamInvalid: Int32 = 0
private let mpvRenderParamSWSize: Int32 = 17
private let mpvRenderParamSWFormat: Int32 = 18
private let mpvRenderParamSWStride: Int32 = 19
private let mpvRenderParamSWPointer: Int32 = 20

/// mpv C 句柄（`mpv_handle*`）。
private typealias MpvHandle = OpaquePointer
/// mpv render C 句柄（`mpv_render_context*`）。
private typealias MpvRenderContext = OpaquePointer

/// `mpv_event`（client.h）。
private struct MpvEvent {
  var eventID: Int32
  var error: Int32
  var replyUserdata: UInt64
  var data: UnsafeMutableRawPointer?
}

/// `mpv_event_property`（client.h）。
private struct MpvEventProperty {
  var name: UnsafePointer<CChar>?
  var format: Int32
  var data: UnsafeMutableRawPointer?
}

/// `mpv_event_end_file`（client.h）。
private struct MpvEventEndFile {
  var reason: Int32
  var error: Int32
  var playlistEntryID: Int64
  var playlistInsertID: Int64
  var playlistInsertNumEntries: Int32
}

/// `mpv_render_param`（render.h）。
private struct MpvRenderParam {
  var type: Int32
  var data: UnsafeMutableRawPointer?
}

// libmpv C API 函数指针签名（与官方头一一对应；仅收录本插件用到的符号）。
private typealias FnMpvCreate = @convention(c) () -> MpvHandle?
private typealias FnMpvInitialize = @convention(c) (MpvHandle?) -> Int32
private typealias FnMpvTerminateDestroy = @convention(c) (MpvHandle?) -> Void
private typealias FnMpvCommand =
  @convention(c) (MpvHandle?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
private typealias FnMpvSetOptionString =
  @convention(c) (MpvHandle?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
private typealias FnMpvSetProperty =
  @convention(c) (MpvHandle?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
private typealias FnMpvGetProperty = FnMpvSetProperty
private typealias FnMpvObserveProperty =
  @convention(c) (MpvHandle?, UInt64, UnsafePointer<CChar>?, Int32) -> Int32
private typealias FnMpvWaitEvent =
  @convention(c) (MpvHandle?, Double) -> UnsafeMutablePointer<MpvEvent>?
private typealias FnMpvErrorString = @convention(c) (Int32) -> UnsafePointer<CChar>?
private typealias FnMpvRenderCreate =
  @convention(c) (UnsafeMutablePointer<MpvRenderContext?>?, MpvHandle?,
                  UnsafeMutablePointer<MpvRenderParam>?) -> Int32
private typealias FnMpvRender =
  @convention(c) (MpvRenderContext?, UnsafeMutablePointer<MpvRenderParam>?) -> Int32
private typealias FnMpvRenderSetUpdate =
  @convention(c) (MpvRenderContext?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?,
                  UnsafeMutableRawPointer?) -> Void
private typealias FnMpvRenderUpdate = @convention(c) (MpvRenderContext?) -> UInt64
private typealias FnMpvRenderFree = @convention(c) (MpvRenderContext?) -> Void

/// libmpv 运行期符号表（`dlopen` + `dlsym` 解析；缺失符号 → 相应能力为空）。
private struct MpvApi {
  var create: FnMpvCreate?
  var initialize: FnMpvInitialize?
  var terminateDestroy: FnMpvTerminateDestroy?
  var command: FnMpvCommand?
  var setOptionString: FnMpvSetOptionString?
  var setProperty: FnMpvSetProperty?
  var getProperty: FnMpvGetProperty?
  var observeProperty: FnMpvObserveProperty?
  var waitEvent: FnMpvWaitEvent?
  var errorString: FnMpvErrorString?
  // render API（R-渲1；可选增强：旧 dylib 缺失时为 nil → 无纹理输出，控制面仍可用）。
  var renderCreate: FnMpvRenderCreate?
  var render: FnMpvRender?
  var renderSetUpdate: FnMpvRenderSetUpdate?
  var renderUpdate: FnMpvRenderUpdate?
  var renderFree: FnMpvRenderFree?
}

/// render 更新回调（C 函数指针；`ctx` 为 `Unmanaged<PlayerPlugin>` 的 opaque 指针）。
private func mpvRenderUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
  guard let ctx = ctx else { return }
  let plugin = Unmanaged<PlayerPlugin>.fromOpaque(ctx).takeUnretainedValue()
  plugin.mpvRenderWake.signal()
}

@objc
public class PlayerPlugin: NSObject, FlutterPlugin {

  // MARK: - 通道与状态

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var itemObservers: [NSKeyValueObservation] = []
  private var endTimeObserver: NSObjectProtocol?
  private var eventSink: FlutterEventSink?

  // MARK: - R-渲1：视频纹理输出面

  /// Flutter 纹理注册表（open 注册 texture、dispose 注销）。
  private var textureRegistry: FlutterTextureRegistry?
  /// 当前输出面纹理句柄（随 open 返回给 Dart）。
  private var textureId: Int64?
  /// AVPlayer 像素输出面（BGRA），供 FlutterTexture.copyPixelBuffer 取帧。
  private var videoOutput: AVPlayerItemVideoOutput?
  /// 取帧轮询定时器（约 60Hz）。
  private var frameTimer: Timer?
  /// 最近一帧（等待 Flutter 采样；跨线程，加锁）。
  private var latestPixelBuffer: CVPixelBuffer?
  private let pixelBufferLock = NSLock()

  // MARK: - Wave G · R-渲3：libmpv 回退后端状态

  /// libmpv 符号表（首次回退 open 时 dlopen 解析，进程内复用）。
  private var mpvApi: MpvApi?
  private var mpvHandle: MpvHandle?
  private var mpvRenderContext: MpvRenderContext?
  /// 当前是否由 libmpv 承载（play/pause/… 分派依据）。
  private var mpvActive = false
  /// libmpv 纹理句柄（render API 可用时才有值）。
  private var mpvTextureId: Int64?
  /// 事件 / 渲染线程运行标志。
  private var mpvRunning = false
  private var mpvRenderRunning = false
  /// 线程退出信号（shutdown 时等待退出，避免释放期仍在使用句柄）。
  private let mpvEventExited = DispatchSemaphore(value: 0)
  private let mpvRenderExited = DispatchSemaphore(value: 0)
  /// 渲染唤醒信号（mpv render update 回调 / 100ms 超时轮询）。
  fileprivate let mpvRenderWake = DispatchSemaphore(value: 0)
  private let mpvEventQueue = DispatchQueue(label: "com.vbox.player.mpv.event")
  private let mpvRenderQueue = DispatchQueue(label: "com.vbox.player.mpv.render")
  /// 最近一帧（libmpv 路径；与 AVPlayer 路径分开，避免互踩）。
  private var mpvLatestPixelBuffer: CVPixelBuffer?
  private let mpvFrameLock = NSLock()
  /// libmpv 状态去重（Buffering / Playing 高频属性变更不重复扰动 Dart 状态机）。
  private var mpvState = "idle"
  private var mpvLastVideoWidth = 0
  private var mpvLastVideoHeight = 0

  private static let methodChannelName = "com.vbox.player/player"
  private static let eventChannelName = "com.vbox.player/player/events"

  // MARK: - 插件注册

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger
    )
    let events = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger
    )
    let instance = PlayerPlugin()
    instance.textureRegistry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)
    events.setStreamHandler(instance)
  }

  // MARK: - MethodChannel 处理

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      open(call, result: result)
    case "play":
      if mpvActive {
        mpvSetFlag("pause", 0)
      } else {
        player?.play()
      }
      result(nil)
    case "pause":
      if mpvActive {
        mpvSetFlag("pause", 1)
      } else {
        player?.pause()
      }
      result(nil)
    case "seekTo":
      seekTo(call, result: result)
    case "setVolume":
      setVolume(call, result: result)
    case "setSpeed":
      setSpeed(call, result: result)
    case "dispose":
      disposePlayer()
      shutdownMpv()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func open(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let url = URL(string: urlString) else {
      result(FlutterError(
        code: "E_INVALID_SOURCE",
        message: "无效的播放源",
        details: nil))
      return
    }

    // A21.5 / R-渲3：复杂封装 → libmpv 回退（不再直接 E_BACKEND_UNAVAILABLE）。
    if needsFallback(urlString) {
      openWithMpv(urlString, args: args, result: result)
      return
    }

    disposePlayer()
    shutdownMpv()

    var assetOptions: [String: Any] = [:]
    if let headers = args["headers"] as? [String: String], !headers.isEmpty {
      assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let asset = AVURLAsset(url: url, options: assetOptions)
    let item = AVPlayerItem(asset: asset)
    // R-渲1：挂视频像素输出面（BGRA），经 FlutterTexture 上屏到 Dart `Texture`。
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    item.add(output)
    videoOutput = output
    let newPlayer = AVPlayer(playerItem: item)
    // 注：iOS 的 AVPlayer.automaticallyWaitsForMinimizeStallingPlayback 为 iOS-only 属性，
    // macOS 不存在该成员（CI Xcode 16.4 / macOS SDK 15.5 编译实证），默认策略即等待最小化卡顿，无需设置。
    player = newPlayer

    observe(newPlayer)
    startFramePolling()
    emitState("opening")
    // R-渲1：注册 Flutter 纹理，并把句柄随 open 返回值交给 Dart。
    // 注册失败（无纹理注册表）→ 返回 nil，Dart 侧 textureId=null → 深色占位。
    if let registry = textureRegistry {
      let id = registry.register(self)
      textureId = id
      result(["textureId": id])
    } else {
      result(nil)
    }
  }

  private func seekTo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let positionMs = call.arguments as? Int else {
      result(FlutterError(code: "E_BAD_ARGUMENT", message: "seekTo 需毫秒整数", details: nil))
      return
    }
    if mpvActive {
      mpvSetDouble("time-pos", Double(positionMs) / 1000.0)
      emitMpvProgress()
      result(nil)
      return
    }
    let seconds = Double(positionMs) / 1000.0
    let target = CMTime(seconds: seconds, preferredTimescale: 600)
    player?.seek(
      to: target,
      toleranceBefore: CMTime.zero,
      toleranceAfter: CMTime.zero,
      completionHandler: { [weak self] _ in self?.emitProgress() }
    )
    result(nil)
  }

  private func setVolume(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let volume = call.arguments as? Double else {
      result(FlutterError(code: "E_BAD_ARGUMENT", message: "setVolume 需浮点数", details: nil))
      return
    }
    let clamped = min(max(volume, 0.0), 1.0)
    if mpvActive {
      mpvSetDouble("volume", clamped * 100.0)  // mpv 音量域 0~100
    } else {
      player?.volume = Float(clamped)
    }
    result(nil)
  }

  private func setSpeed(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let speed = call.arguments as? Double else {
      result(FlutterError(code: "E_BAD_ARGUMENT", message: "setSpeed 需浮点数", details: nil))
      return
    }
    let clamped = min(max(speed, 0.25), 4.0)
    if mpvActive {
      mpvSetDouble("speed", clamped)
    } else {
      player?.rate = Float(clamped)
    }
    result(nil)
  }

  // MARK: - 观察与事件

  private func observe(_ player: AVPlayer) {
    itemObservers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      guard let self = self, let p = self.player else { return }
      switch p.timeControlStatus {
      case .waitingToPlayAtSpecifiedRate:
        self.emitState("buffering")
      case .playing:
        self.emitState("playing")
      case .paused:
        self.emitState("paused")
      @unknown default:
        self.emitState("paused")
      }
    })
    itemObservers.append(player.observe(\.currentItem?.status, options: [.new]) { [weak self] _, _ in
      guard let self = self, let p = self.player else { return }
      switch p.currentItem?.status {
      case .readyToPlay:
        self.emitProgress()
      case .failed:
        self.emitError(p.currentItem?.error?.localizedDescription ?? "播放失败", fatal: true)
      case .none:
        self.emitState("idle")
      case .unknown?:
        break
      @unknown default:
        break
      }
    })
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in
      self?.emitProgress()
    }
    if let item = player.currentItem {
      // R-渲1：视频尺寸上报（Dart 侧输出面按纵横比自适应，对齐 videoGravity=.resizeAspect）。
      itemObservers.append(item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
        let size = item.presentationSize
        if size.width > 0 && size.height > 0 {
          self?.emitVideoSize(Int(size.width), Int(size.height))
        }
      })
      endTimeObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.emitState("ended")
      }
    }
  }

  // MARK: - R-渲1：取帧与纹理输出

  /// 启动取帧轮询（约 60Hz；主线程定时器）。
  private func startFramePolling() {
    frameTimer?.invalidate()
    frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
      [weak self] _ in
      self?.pollFrame()
    }
  }

  /// 拉取 AVPlayerItemVideoOutput 的新帧并通知 Flutter 纹理可采样。
  private func pollFrame() {
    guard let output = videoOutput, player?.currentItem != nil else { return }
    let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
    guard output.hasNewPixelBuffer(forItemTime: itemTime),
          let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
    else { return }
    pixelBufferLock.lock()
    latestPixelBuffer = buffer
    pixelBufferLock.unlock()
    if let id = textureId {
      textureRegistry?.textureFrameAvailable(id)
    }
  }

  private func emitVideoSize(_ width: Int, _ height: Int) {
    eventSink?(["type": "videoSize", "width": width, "height": height])
  }

  private func emitState(_ value: String) {
    eventSink?(["type": "state", "value": value])
  }

  private func emitProgress() {
    guard let item = player?.currentItem else { return }
    let durationSeconds = CMTimeGetSeconds(item.duration)
    let positionSeconds = CMTimeGetSeconds(item.currentTime())
    let bufferedSeconds = item.loadedTimeRanges
      .last?.timeRangeValue.end.seconds ?? 0.0
    let isLive = durationSeconds.isNaN || durationSeconds.isInfinite
      || item.duration == .indefinite
    eventSink?([
      "type": "progress",
      "positionMs": Int(positionSeconds.isNaN ? 0 : positionSeconds * 1000.0),
      "durationMs": Int(durationSeconds.isNaN || isLive ? 0 : durationSeconds * 1000.0),
      "bufferedMs": Int(bufferedSeconds.isNaN ? 0 : bufferedSeconds * 1000.0),
      "isLive": isLive,
    ])
  }

  private func emitError(_ message: String, fatal: Bool) {
    eventSink?(["type": "error", "message": message, "fatal": fatal])
  }

  // MARK: - 释放

  private func disposePlayer() {
    frameTimer?.invalidate()
    frameTimer = nil
    if let item = player?.currentItem, let output = videoOutput {
      item.remove(output)
    }
    videoOutput = nil
    pixelBufferLock.lock()
    latestPixelBuffer = nil
    pixelBufferLock.unlock()
    if let id = textureId {
      textureRegistry?.unregisterTexture(id)
    }
    textureId = nil
    itemObservers.removeAll()
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }
    if let observer = endTimeObserver {
      NotificationCenter.default.removeObserver(observer)
      endTimeObserver = nil
    }
    player?.pause()
    player = nil
  }

  // MARK: - A21.5 判定（与 Dart `PlayerBackendSelector.needsFallback` 同清单）

  private func needsFallback(_ url: String) -> Bool {
    let lower = url.lowercased()
    for ext in [".mkv", ".flv", ".ts", ".rmvb", ".avi", ".wmv", ".m2ts"] {
      if lower.contains(ext) {
        return true
      }
    }
    return false
  }
}

// ═══════════════ Wave G · R-渲3：libmpv 回退后端实现 ═══════════════

extension PlayerPlugin {

  // MARK: - 符号加载（D28 随包分发）

  /// dlopen `libmpv.dylib` 并解析符号表；已加载则复用。失败返回 false。
  private func loadMpvApi() -> Bool {
    if mpvApi != nil { return true }
    var candidates: [String] = []
    if let frameworks = Bundle.main.privateFrameworksPath {
      candidates.append(frameworks + "/libmpv.dylib")
    }
    candidates.append(Bundle.main.bundlePath + "/Contents/Frameworks/libmpv.dylib")
    candidates.append("libmpv.dylib")

    var lib: UnsafeMutableRawPointer?
    for path in candidates {
      if let handle = dlopen(path, RTLD_NOW) {
        lib = handle
        break
      }
    }
    guard let library = lib else {
      NSLog("vbox: libmpv.dylib 加载失败（D28 分发缺失），复杂封装回退不可用")
      return false
    }

    func sym(_ name: String) -> UnsafeMutableRawPointer? { dlsym(library, name) }

    guard let createSym = sym("mpv_create"),
          let initSym = sym("mpv_initialize"),
          let destroySym = sym("mpv_terminate_destroy"),
          let commandSym = sym("mpv_command"),
          let setOptionSym = sym("mpv_set_option_string"),
          let setPropSym = sym("mpv_set_property"),
          let getPropSym = sym("mpv_get_property"),
          let observeSym = sym("mpv_observe_property"),
          let waitSym = sym("mpv_wait_event"),
          let errorSym = sym("mpv_error_string")
    else {
      NSLog("vbox: libmpv.dylib 核心符号不完整，复杂封装回退不可用")
      return false
    }

    var api = MpvApi()
    api.create = unsafeBitCast(createSym, to: FnMpvCreate.self)
    api.initialize = unsafeBitCast(initSym, to: FnMpvInitialize.self)
    api.terminateDestroy = unsafeBitCast(destroySym, to: FnMpvTerminateDestroy.self)
    api.command = unsafeBitCast(commandSym, to: FnMpvCommand.self)
    api.setOptionString = unsafeBitCast(setOptionSym, to: FnMpvSetOptionString.self)
    api.setProperty = unsafeBitCast(setPropSym, to: FnMpvSetProperty.self)
    api.getProperty = unsafeBitCast(getPropSym, to: FnMpvGetProperty.self)
    api.observeProperty = unsafeBitCast(observeSym, to: FnMpvObserveProperty.self)
    api.waitEvent = unsafeBitCast(waitSym, to: FnMpvWaitEvent.self)
    api.errorString = unsafeBitCast(errorSym, to: FnMpvErrorString.self)
    // render API 为可选增强（R-渲1）：缺失时控制面可用但无纹理输出。
    if let s = sym("mpv_render_context_create") {
      api.renderCreate = unsafeBitCast(s, to: FnMpvRenderCreate.self)
    }
    if let s = sym("mpv_render_context_render") {
      api.render = unsafeBitCast(s, to: FnMpvRender.self)
    }
    if let s = sym("mpv_render_context_set_update_callback") {
      api.renderSetUpdate = unsafeBitCast(s, to: FnMpvRenderSetUpdate.self)
    }
    if let s = sym("mpv_render_context_update") {
      api.renderUpdate = unsafeBitCast(s, to: FnMpvRenderUpdate.self)
    }
    if let s = sym("mpv_render_context_free") {
      api.renderFree = unsafeBitCast(s, to: FnMpvRenderFree.self)
    }
    mpvApi = api
    return true
  }

  // MARK: - 打开（复杂封装回退）

  private func openWithMpv(
    _ urlString: String,
    args: [String: Any],
    result: @escaping FlutterResult
  ) {
    guard loadMpvApi(), let api = mpvApi else {
      result(FlutterError(
        code: "E_BACKEND_UNAVAILABLE",
        message: "libmpv 动态库加载失败（D28 分发缺失），复杂封装不可播",
        details: urlString))
      return
    }

    disposePlayer()
    shutdownMpv()

    guard let handle = api.create?() else {
      result(FlutterError(
        code: "E_BACKEND_UNAVAILABLE",
        message: "libmpv 初始化失败", details: urlString))
      return
    }

    // R-渲1：有 render API 时走 `vo=libmpv`（render_context 前置），否则退回 `vo=null`
    // （纯控制面，无纹理输出）。vo 属初始化前生效选项，必须早于 mpv_initialize。
    let canRender = api.renderCreate != nil
    _ = canRender
      ? api.setOptionString?(handle, "vo", "libmpv")
      : api.setOptionString?(handle, "vo", "null")

    if (api.initialize?(handle) ?? -1) < 0 {
      api.terminateDestroy?(handle)
      result(FlutterError(
        code: "E_BACKEND_UNAVAILABLE",
        message: "libmpv 初始化失败", details: urlString))
      return
    }
    mpvHandle = handle
    mpvActive = true
    mpvState = "opening"

    // 直播直接起播；点播保持暂停待 Dart play()（对齐 Android / Windows 口径）。
    let isLive = args["isLive"] as? Bool ?? false
    mpvSetFlag("pause", isLive ? 0 : 1)

    // 自定义请求头 → http-header-fields（loadfile 时生效）。
    if let headers = args["headers"] as? [String: String], !headers.isEmpty {
      let joined = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
      joined.withCString { api.setOptionString?(handle, "http-header-fields", $0) }
    }

    // loadfile（replace：单文件播放，与 Android / Windows 语义一致）。
    let loadResult: Int32 = "loadfile".withCString { load in
      urlString.withCString { url in
        "replace".withCString { replace in
          var argv: [UnsafePointer<CChar>?] = [load, url, replace, nil]
          return api.command?(handle, &argv) ?? -1
        }
      }
    }
    if loadResult < 0 {
      shutdownMpv()
      result(FlutterError(
        code: "E_OPEN", message: "loadfile 命令失败", details: urlString))
      return
    }

    // 进度 / 状态由属性变更驱动（对齐契约 §2.5 能力矩阵）。
    _ = api.observeProperty?(handle, 0, "time-pos", mpvFormatDouble)
    _ = api.observeProperty?(handle, 0, "duration", mpvFormatDouble)
    _ = api.observeProperty?(handle, 0, "pause", mpvFormatFlag)
    _ = api.observeProperty?(handle, 0, "paused-for-cache", mpvFormatFlag)
    _ = api.observeProperty?(handle, 0, "demuxer-cache-time", mpvFormatDouble)

    if canRender {
      setupMpvRenderContext()
    }

    // 事件线程（0.1s 超时轮询，支持 mpvRunning 标志及时退出）。
    mpvRunning = true
    let runtime = self
    mpvEventQueue.async {
      runtime.mpvEventLoop()
      runtime.mpvEventExited.signal()
    }

    emitState("opening")
    if let id = mpvTextureId {
      result(["textureId": id])
    } else {
      result([String: Any]())
    }
  }

  // MARK: - 属性读写辅助

  private func mpvSetFlag(_ name: String, _ value: Int32) {
    guard let api = mpvApi, let handle = mpvHandle else { return }
    var flag = value
    withUnsafeMutablePointer(to: &flag) { pointer in
      name.withCString {
        api.setProperty?(handle, $0, mpvFormatFlag, UnsafeMutableRawPointer(pointer))
      }
    }
  }

  private func mpvSetDouble(_ name: String, _ value: Double) {
    guard let api = mpvApi, let handle = mpvHandle else { return }
    var number = value
    withUnsafeMutablePointer(to: &number) { pointer in
      name.withCString {
        api.setProperty?(handle, $0, mpvFormatDouble, UnsafeMutableRawPointer(pointer))
      }
    }
  }

  private func mpvGetDouble(_ name: String) -> Double? {
    guard let api = mpvApi, let handle = mpvHandle else { return nil }
    var value = 0.0
    let rc: Int32 = withUnsafeMutablePointer(to: &value) { pointer in
      name.withCString {
        api.getProperty?(handle, $0, mpvFormatDouble, UnsafeMutableRawPointer(pointer)) ?? -1
      }
    }
    return rc < 0 ? nil : value
  }

  private func mpvGetInt64(_ name: String) -> Int64? {
    guard let api = mpvApi, let handle = mpvHandle else { return nil }
    var value: Int64 = 0
    let rc: Int32 = withUnsafeMutablePointer(to: &value) { pointer in
      name.withCString {
        api.getProperty?(handle, $0, mpvFormatInt64, UnsafeMutableRawPointer(pointer)) ?? -1
      }
    }
    return rc < 0 ? nil : value
  }

  private func mpvGetFlag(_ name: String) -> Int32? {
    guard let api = mpvApi, let handle = mpvHandle else { return nil }
    var value: Int32 = 0
    let rc: Int32 = withUnsafeMutablePointer(to: &value) { pointer in
      name.withCString {
        api.getProperty?(handle, $0, mpvFormatFlag, UnsafeMutableRawPointer(pointer)) ?? -1
      }
    }
    return rc < 0 ? nil : value
  }

  // MARK: - 事件线程

  private func mpvEventLoop() {
    guard let api = mpvApi, let handle = mpvHandle else { return }
    while mpvRunning {
      guard let event = api.waitEvent?(handle, 0.1) else { continue }
      if event.pointee.eventID == mpvEventShutdown { break }
      handleMpvEvent(event.pointee)
    }
  }

  private func handleMpvEvent(_ event: MpvEvent) {
    let api = mpvApi
    switch event.eventID {
    case mpvEventStartFile:
      mpvEmitState("opening")
    case mpvEventFileLoaded:
      let paused = mpvGetFlag("pause") ?? 0
      mpvEmitState(paused != 0 ? "paused" : "playing")
      emitMpvProgress()
    case mpvEventPlaybackRestart:
      let paused = mpvGetFlag("pause") ?? 0
      mpvEmitState(paused != 0 ? "paused" : "playing")
    case mpvEventEndFile:
      guard let raw = event.data else { break }
      let endFile = raw.assumingMemoryBound(to: MpvEventEndFile.self).pointee
      if endFile.reason == mpvEndFileReasonError {
        var detail = "播放失败"
        if let cString = api?.errorString?(endFile.error) {
          detail = String(cString: cString)
        }
        mpvEmitError(detail, fatal: true)
        mpvEmitState("error")
      } else if endFile.reason == mpvEndFileReasonEOF {
        mpvEmitState("ended")
      }
    case mpvEventPropertyChange:
      guard let raw = event.data else { break }
      let property = raw.assumingMemoryBound(to: MpvEventProperty.self).pointee
      let name = property.name.map { String(cString: $0) } ?? ""
      switch name {
      case "time-pos", "duration":
        emitMpvProgress()
      case "pause":
        if property.format == mpvFormatFlag, let data = property.data {
          let paused = data.assumingMemoryBound(to: Int32.self).pointee
          mpvEmitState(paused != 0 ? "paused" : "playing")
        }
      case "paused-for-cache":
        if property.format == mpvFormatFlag, let data = property.data {
          let caching = data.assumingMemoryBound(to: Int32.self).pointee
          if caching != 0 {
            mpvEmitState("buffering")
          } else {
            let paused = mpvGetFlag("pause") ?? 0
            mpvEmitState(paused != 0 ? "paused" : "playing")
          }
        }
      default:
        break
      }
    default:
      break
    }
  }

  /// 状态去重上报（libmpv → Dart 事件，主线程同步）。
  private func mpvEmitState(_ value: String) {
    if mpvState == value { return }
    mpvState = value
    DispatchQueue.main.async { [weak self] in self?.emitState(value) }
  }

  private func mpvEmitError(_ message: String, fatal: Bool) {
    DispatchQueue.main.async { [weak self] in self?.emitError(message, fatal: fatal) }
  }

  private func emitMpvProgress() {
    guard mpvHandle != nil else { return }
    let positionSeconds = mpvGetDouble("time-pos") ?? -1.0
    let durationSeconds = mpvGetDouble("duration") ?? -1.0
    let bufferedSeconds = mpvGetDouble("demuxer-cache-time") ?? -1.0
    let isLive = durationSeconds < 0.0
    let payload: [String: Any] = [
      "type": "progress",
      "positionMs": positionSeconds < 0 ? 0 : Int(positionSeconds * 1000.0),
      "durationMs": isLive ? 0 : Int(durationSeconds * 1000.0),
      "bufferedMs": bufferedSeconds < 0 ? 0 : Int(bufferedSeconds * 1000.0),
      "isLive": isLive,
    ]
    DispatchQueue.main.async { [weak self] in self?.eventSink?(payload) }
  }

  // MARK: - 渲染输出面（R-渲1：SW 软渲染 → CVPixelBuffer → FlutterTexture）

  private func setupMpvRenderContext() {
    guard let api = mpvApi, let handle = mpvHandle,
          let create = api.renderCreate else { return }

    let renderContext: MpvRenderContext? = "sw".withCString { apiType -> MpvRenderContext? in
      var context: MpvRenderContext?
      var params = [
        MpvRenderParam(type: mpvRenderParamAPIType,
                       data: UnsafeMutableRawPointer(mutating: apiType)),
        MpvRenderParam(type: mpvRenderParamInvalid, data: nil),
      ]
      let rc = create(&context, handle, &params)
      return rc < 0 ? nil : context
    }
    guard let ctx = renderContext else {
      // 无纹理输出：Dart 侧深色占位，控制面（播放 / 进度）不受影响。
      return
    }
    mpvRenderContext = ctx

    if let id = textureRegistry?.register(self) {
      mpvTextureId = id
    }

    api.renderSetUpdate?(
      ctx, mpvRenderUpdateCallback, Unmanaged.passUnretained(self).toOpaque())

    mpvRenderRunning = true
    let runtime = self
    mpvRenderQueue.async {
      runtime.mpvRenderLoop()
      runtime.mpvRenderExited.signal()
    }
  }

  private func mpvRenderLoop() {
    while mpvRenderRunning {
      _ = mpvRenderWake.wait(timeout: .now() + 0.1)
      if !mpvRenderRunning { break }
      guard let api = mpvApi, let ctx = mpvRenderContext else { continue }
      _ = api.renderUpdate?(ctx)
      renderMpvFrame()
    }
  }

  private func renderMpvFrame() {
    guard let api = mpvApi, let ctx = mpvRenderContext, api.render != nil else { return }

    // 视频目标尺寸：优先 coded 尺寸（width/height），回退 display 尺寸（dwidth/dheight）。
    var width = mpvGetInt64("width") ?? 0
    var height = mpvGetInt64("height") ?? 0
    if width <= 0 || height <= 0 {
      width = mpvGetInt64("dwidth") ?? 0
      height = mpvGetInt64("dheight") ?? 0
    }
    guard width > 0, height > 0 else { return }  // 尚未解出视频轨（纯音频 / 加载中）

    let pixelWidth = Int(width)
    let pixelHeight = Int(height)
    let sourceStride = pixelWidth * 4
    var scratch = [UInt8](repeating: 0, count: sourceStride * pixelHeight)

    var stride = Int32(sourceStride)
    var size = [Int32(pixelWidth), Int32(pixelHeight)]
    var format = Array("bgra".utf8CString)

    let renderResult: Int32 = withUnsafeMutablePointer(to: &stride) { stridePointer -> Int32 in
      size.withUnsafeMutableBufferPointer { sizeBuffer -> Int32 in
        format.withUnsafeMutableBufferPointer { formatBuffer -> Int32 in
          scratch.withUnsafeMutableBytes { scratchBuffer -> Int32 in
            var params = [
              MpvRenderParam(
                type: mpvRenderParamSWSize,
                data: UnsafeMutableRawPointer(sizeBuffer.baseAddress)),
              MpvRenderParam(
                type: mpvRenderParamSWFormat,
                data: UnsafeMutableRawPointer(formatBuffer.baseAddress)),
              MpvRenderParam(
                type: mpvRenderParamSWStride,
                data: UnsafeMutableRawPointer(stridePointer)),
              MpvRenderParam(
                type: mpvRenderParamSWPointer,
                data: scratchBuffer.baseAddress),
              MpvRenderParam(type: mpvRenderParamInvalid, data: nil),
            ]
            return api.render?(ctx, &params) ?? -1
          }
        }
      }
    }
    guard renderResult >= 0 else { return }

    guard let pixelBuffer = Self.makePixelBuffer(
      from: scratch, width: pixelWidth, height: pixelHeight, sourceStride: sourceStride)
    else { return }

    mpvFrameLock.lock()
    mpvLatestPixelBuffer = pixelBuffer
    mpvFrameLock.unlock()

    if let id = mpvTextureId {
      textureRegistry?.textureFrameAvailable(id)
    }

    // 视频尺寸变更上报（Dart 侧输出面纵横比自适应；去重避免抖动）。
    if pixelWidth != mpvLastVideoWidth || pixelHeight != mpvLastVideoHeight {
      mpvLastVideoWidth = pixelWidth
      mpvLastVideoHeight = pixelHeight
      DispatchQueue.main.async { [weak self] in
        self?.emitVideoSize(pixelWidth, pixelHeight)
      }
    }
  }

  /// BGRA 软渲染结果 → CVPixelBuffer（FlutterTexture 采样面）。
  private static func makePixelBuffer(
    from bytes: [UInt8],
    width: Int,
    height: Int,
    sourceStride: Int
  ) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: false,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: false,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      attributes as CFDictionary, &pixelBuffer)
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let destinationStride = CVPixelBufferGetBytesPerRow(buffer)
    let copyBytes = min(sourceStride, destinationStride)
    bytes.withUnsafeBytes { source in
      guard let sourceBase = source.baseAddress else { return }
      for row in 0..<height {
        _ = memcpy(
          base.advanced(by: row * destinationStride),
          sourceBase.advanced(by: row * sourceStride),
          copyBytes)
      }
    }
    return buffer
  }

  // MARK: - libmpv 释放

  private func shutdownMpv() {
    // 1. 停渲染线程（避免释放 render_context 时仍在渲染）。
    if mpvRenderRunning {
      mpvRenderRunning = false
      mpvRenderWake.signal()
      _ = mpvRenderExited.wait(timeout: .now() + 2)
    }
    if let ctx = mpvRenderContext {
      mpvApi?.renderSetUpdate?(ctx, nil, nil)
      mpvApi?.renderFree?(ctx)
      mpvRenderContext = nil
    }
    if let id = mpvTextureId {
      textureRegistry?.unregisterTexture(id)
      mpvTextureId = nil
    }
    mpvFrameLock.lock()
    mpvLatestPixelBuffer = nil
    mpvFrameLock.unlock()
    mpvLastVideoWidth = 0
    mpvLastVideoHeight = 0

    // 2. 停事件线程（0.1s 超时轮询 → 最迟 ~0.1s 退出）。
    if mpvRunning {
      mpvRunning = false
      _ = mpvEventExited.wait(timeout: .now() + 2)
    }
    if let handle = mpvHandle {
      mpvApi?.terminateDestroy?(handle)
      mpvHandle = nil
    }
    mpvActive = false
    mpvState = "idle"
  }
}

// MARK: - EventChannel

extension PlayerPlugin: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    // 已有播放器时补发一次当前状态，避免 Dart 侧错过中间态。
    if mpvActive {
      emitMpvProgress()
    } else if player != nil {
      emitProgress()
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

// MARK: - FlutterTexture（R-渲1）

extension PlayerPlugin: FlutterTexture {
  /// Flutter 采样回调（raster 线程）：交出最近一帧 BGRA 像素缓冲。
  ///
  /// 无新帧时返回 nil，引擎沿用上一帧画面；缓冲区以 `passRetained` 移交，
  /// 由引擎负责释放。AVPlayer / libmpv 两路各自独立缓冲，按当前后端取向。
  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    if mpvActive {
      mpvFrameLock.lock()
      defer { mpvFrameLock.unlock() }
      guard let buffer = mpvLatestPixelBuffer else { return nil }
      mpvLatestPixelBuffer = nil
      return Unmanaged.passRetained(buffer)
    }
    pixelBufferLock.lock()
    defer { pixelBufferLock.unlock() }
    guard let buffer = latestPixelBuffer else { return nil }
    latestPixelBuffer = nil
    return Unmanaged.passRetained(buffer)
  }
}
