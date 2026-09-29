import Foundation
import Flutter

/// macOS 版 NodeBridge 插件。
///
/// 与 iOS（内嵌 NodeMobile.framework）不同，macOS 上 Node.js 以
/// **受签名校验的子进程**方式运行（官方 dmg 发布签名后的 node 二进制
/// 放在 app bundle 内），bootstrap 模板中 TVS_PARENT_PID 看门狗保证
/// Flutter 父进程被杀后 node 子进程及时退出。
public class NodeBridgePlugin: NSObject, FlutterPlugin {
    public static let channelName = "com.example.tvs/node_bridge"
    public static let port = 9775
    public static let dartPort = 9776

    private var registrar: FlutterPluginRegistrar?
    private var channel: FlutterMethodChannel?

    private var process: Process?
    private var isRunning = false
    private var documentDirectory = URL(fileURLWithPath: ".")

    public func register(with registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        channel = FlutterMethodChannel(name: Self.channelName,
                                       binaryMessenger: registrar.messenger())
        channel?.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    public func detachFromEngine(for registrar: FlutterEngine) {
        stopNode()
        channel?.setMethodCallHandler(nil)
        channel = nil
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startNode":
            let args = call.arguments as? [String: Any] ?? [:]
            let bundlePath = args["bundlePath"] as? String ?? ""
            startNode(bundlePath: bundlePath) { port in
                DispatchQueue.main.async {
                    port > 0 ? result(port)
                    : result(FlutterError(code: "START_FAILED",
                                           message: "node spawn failed",
                                           details: nil))
                }
            }
        case "isRunning": result(isRunning)
        case "getNodePort": result(Self.port)
        case "getDartPort": result(Self.dartPort)
        case "stopNode":
            stopNode(); result(true)
        case "getVersion": result("1.2.3 (8)")
        case "getPackageInfo":
            result(["packageName": "com.example.tvs",
                   "versionName": "1.2.3",
                   "versionCode": 8,
                   "platform": "macos"])
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func startNode(bundlePath: String,
                           onReady: @escaping (Int) -> Void) {
        guard !isRunning else { onReady(Self.port); return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { onReady(0); return }

            // node 二进制位于 app bundle 内（受签名校验），由构建期拷贝。
            let node = Bundle.main.bundlePath + "/Contents/MacOS/node"
            guard FileManager.default.fileExists(atPath: node) else {
                onReady(0); return
            }

            let nodeDir = self.documentDirectory.appendingPathComponent(
                "node", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: nodeDir, withIntermediateDirectories: true)

            let p = Process()
            p.executableURL = URL(fileURLWithPath: node)
            p.currentDirectoryURL = nodeDir
            p.environment = [
                "PORT": String(Self.port),
                "DART_PORT": String(Self.dartPort),
                "BUNDLE_PATH": bundlePath,
                "NODE_PATH": nodeDir.path,
                "TVS_PARENT_PID": String(ProcessInfo.processInfo.processIdentifier),
            ]
            p.arguments = [bundlePath]
            p.terminationHandler = { [weak self] _ in
                self?.isRunning = false
            }

            do {
                try p.run()
                self.process = p
                self.isRunning = true

                // 轮询 .startup.ack 确认 HTTP server 就绪。
                let ack = nodeDir.appendingPathComponent(".startup.ack")
                let start = Date()
                while Date().timeIntervalSince(start) < 45 {
                    if FileManager.default.fileExists(atPath: ack.path) {
                        onReady(Self.port)
                        return
                    }
                    try? Thread.sleep(forTimeInterval: 0.5)
                }
                onReady(0)
            } catch {
                onReady(0)
            }
        }
    }

    private func stopNode() {
        isRunning = false
        if let p = process {
            p.terminate()
        }
        process = nil
    }
}
