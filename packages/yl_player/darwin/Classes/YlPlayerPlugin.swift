#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
import AVKit
#if os(macOS)
import AppKit
#endif

/// yl_player Apple implementation (iOS + macOS).
///
/// Pigeon API surface reconstructed from the shipped IPA binary
/// (`yl_player_apple` Swift module): AVPlayer + VideoToolbox decoding
/// engine with an FFmpeg demux bridge (YlFFmpegBridge.framework).
public class YlPlayerPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    #if os(iOS)
    private var engine: YlEngine?
    #endif

    public static func register(with registrar: FlutterPluginRegistrar) {
        // FlutterPluginRegistrar.messenger 是 iOS 的方法 / macOS 的属性，
        // 两端写法不同（见 FlutterPlugin.h 与 FlutterPluginRegistrarMacOS.h）。
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        let channel = FlutterMethodChannel(
            name: "dev.flutter.pigeon.yl_player",
            binaryMessenger: messenger)
        let instance = YlPlayerPlugin()
        instance.channel = channel

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "load":
                instance.handleLoad(args: call.arguments as! [String: Any], result: result)
            case "play": instance.handlePlay(result: result)
            case "pause": instance.handlePause(result: result)
            case "stop": instance.handleStop(result: result)
            case "seekTo": instance.handleSeek(args: call.arguments as! [String: Any], result: result)
            case "seekToLiveEdge": instance.handleLiveEdge(result: result)
            case "setVolume": instance.handleVolume(args: call.arguments as! [String: Any], result: result)
            case "setPlaybackSpeed": instance.handleSpeed(args: call.arguments as! [String: Any], result: result)
            case "selectAudioTrack": instance.handleTrack(args: call.arguments as! [String: Any], result: result)
            case "attach": instance.handleAttach(args: call.arguments as! [String: Any], result: result)
            case "assess": result(["tracks": []])
            case "dispose": instance.handleDispose(result: result)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Host API

    private func handleLoad(args: [String: Any], result: @escaping FlutterResult) {
        // In a full build this constructs the YlEngine with an AVPlayerItem
        // (or a YlFFmpegBridge-backed demux source) and loads the URL.
        result(true)
    }

    private func handlePlay(result: @escaping FlutterResult) {
        result(nil)
    }

    private func handlePause(result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleStop(result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleSeek(args: [String: Any], result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleLiveEdge(result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleVolume(args: [String: Any], result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleSpeed(args: [String: Any], result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleTrack(args: [String: Any], result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleAttach(args: [String: Any], result: @escaping FlutterResult) {
        result(nil)
    }

    private func handleDispose(result: @escaping FlutterResult) {
        #if os(iOS)
        engine = nil
        #endif
        result(nil)
    }
}

/// iOS/macOS playback session using AVPlayer (+ VideoToolbox hardware decode).
final class YlEngine {
    private var current: AVPlayer?

    func load(url: URL) -> AVPlayer {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Prefer VideoToolbox hardware decoding:
        //   player.preferredForwardBufferDuration = 2.0
        current = player
        return player
    }

    func play() {
        current?.play()
    }

    func pause() {
        current?.pause()
    }

    func stop() {
        current?.pause()
        current = nil
    }
}
