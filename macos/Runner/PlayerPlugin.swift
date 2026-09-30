//
//  PlayerPlugin.swift
//  Runner
//
//  macOS 播放器插件（AVPlayer 主后端）。
//
//  对齐契约 §2.5 播放器能力矩阵 + A21.5 回退策略 + iOS `PlayerEngine` 协议（type/state/event）：
//    · MethodChannel `com.vbox.player/player`：open / play / pause / seekTo / setVolume / setSpeed / dispose
//    · EventChannel `com.vbox.player/player/events`：state / progress / error
//  与 Android `PlayerPlugin.kt` 共用同一 wire 协议（Dart `ChannelPlayer._onEvent` 解析面）。
//
//  A21.5：复杂封装（MKV / FLV / TS / RMVB / AVI / WMV / M2TS）当前 AVPlayer 不支持，
//  返回 `E_BACKEND_UNAVAILABLE`，由 Dart `PlayerController` 降级链回退；
//  libmpv 回退实现在 G-02-B 原生二进制分发决策（D28）后接入。
//

import AVFoundation
import FlutterMacOS
import Foundation

@objc
public class PlayerPlugin: NSObject, FlutterPlugin {

  // MARK: - 通道与状态

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var itemObservers: [NSKeyValueObservation] = []
  private var endTimeObserver: NSObjectProtocol?
  private var eventSink: FlutterEventSink?

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
    registrar.addMethodCallDelegate(instance, channel: channel)
    events.setStreamHandler(instance)
  }

  // MARK: - MethodChannel 处理

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      open(call, result: result)
    case "play":
      player?.play()
      result(nil)
    case "pause":
      player?.pause()
      result(nil)
    case "seekTo":
      seekTo(call, result: result)
    case "setVolume":
      setVolume(call, result: result)
    case "setSpeed":
      setSpeed(call, result: result)
    case "dispose":
      disposePlayer()
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

    // A21.5：复杂封装当前 AVPlayer 不支持 → 交 Dart 侧降级链回退（libmpv 待 G-02-B 分发后接入）。
    if needsFallback(urlString) {
      result(FlutterError(
        code: "E_BACKEND_UNAVAILABLE",
        message: "AVPlayer 不支持复杂封装（A21.5），需 libmpv 回退",
        details: urlString))
      return
    }

    disposePlayer()

    var assetOptions: [String: Any] = [:]
    if let headers = args["headers"] as? [String: String], !headers.isEmpty {
      assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let asset = AVURLAsset(url: url, options: assetOptions)
    let item = AVPlayerItem(asset: asset)
    let newPlayer = AVPlayer(playerItem: item)
    // 注：iOS 的 AVPlayer.automaticallyWaitsForMinimizeStallingPlayback 为 iOS-only 属性，
    // macOS 不存在该成员（CI Xcode 16.4 / macOS SDK 15.5 编译实证），默认策略即等待最小化卡顿，无需设置。
    player = newPlayer

    observe(newPlayer)
    emitState("opening")
    result(nil)
  }

  private func seekTo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let positionMs = call.arguments as? Int else {
      result(FlutterError(code: "E_BAD_ARGUMENT", message: "seekTo 需毫秒整数", details: nil))
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
    player?.volume = Float(min(max(volume, 0.0), 1.0))
    result(nil)
  }

  private func setSpeed(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let speed = call.arguments as? Double else {
      result(FlutterError(code: "E_BAD_ARGUMENT", message: "setSpeed 需浮点数", details: nil))
      return
    }
    player?.rate = Float(min(max(speed, 0.25), 4.0))
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
      endTimeObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.emitState("ended")
      }
    }
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

// MARK: - EventChannel

extension PlayerPlugin: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    // 已有播放器时补发一次当前状态，避免 Dart 侧错过中间态。
    if player != nil {
      emitProgress()
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
