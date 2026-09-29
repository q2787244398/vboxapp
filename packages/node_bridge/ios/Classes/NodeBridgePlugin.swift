import Flutter
import Foundation
import NodeMobile

/// TVS 的 iOS 侧 Node 桥。
///
/// 与 Dart 侧 `NodeService` 的契约（MethodChannel com.example.tvs/node_bridge）：
///   startNode {bundlePath: String} -> Int   成功返回端口(>0)，失败返回 0
///   isRunning                      -> Bool
///   getNodePort                    -> Int
///   getDartPort                    -> Int
///   stopNode                       -> Bool
///
/// 说明：
/// - `bundlePath` 传的是 **node 工程目录的绝对路径**（JS 文件与占位符替换由 Dart 侧
///   在调用前准备好），本插件只负责设环境变量并执行 `node_start`。
/// - nodejs-mobile 的 iOS 框架只导出两个 C 函数：`node_start(argc, argv)` 与
///   `node_is_initialized()`（见 NodeMobile.xcframework 的 Headers/NodeMobile.h）。
///   官方示例里那个 `NodeRunner` 类是示例自己写的封装，不是框架 API。
/// - `node_start` 会阻塞到 Node 事件循环退出，因此必须在后台线程调用。
public class NodeBridgePlugin: NSObject, FlutterPlugin {

    private static let channelName = "com.example.tvs/node_bridge"
    private static let defaultPort = 9775
    private static let defaultDartPort = 9776
    private static let startupTimeout: TimeInterval = 180

    private var port = defaultPort
    private var dartPort = defaultDartPort

    private static var nodeStarted = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger())
        let instance = NodeBridgePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startNode":
            let args = call.arguments as? [String: Any] ?? [:]
            let nodeDir = (args["nodeDir"] as? String) ?? ""
            startNode(nodeDir: nodeDir, result: result)

        case "isRunning":
            result(Self.nodeStarted && isPortOpen())

        case "getNodePort":
            result(port)

        case "getDartPort":
            result(dartPort)

        case "stopNode":
            // 进程内嵌的 Node 没有安全的停机接口（node_start 阻塞在事件循环里）。
            // 官方 nodejs-mobile 同样只提供启动/查询，这里如实返回 false。
            NSLog("[TVS-NodeBridge] stopNode: in-process Node cannot be stopped")
            result(false)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 启动

    private func startNode(nodeDir: String, result: @escaping FlutterResult) {
        if Self.nodeStarted && isPortOpen() {
            result(port)
            return
        }
        if Self.nodeStarted {
            // 已经在启动过程中
            result(0)
            return
        }
        guard !nodeDir.isEmpty else {
            result(FlutterError(code: "INVALID_ARG",
                                message: "nodeDir is required",
                                details: nil))
            return
        }
        Self.nodeStarted = true

        let entry = (nodeDir as NSString).appendingPathComponent("node-main-template.js")
        guard FileManager.default.fileExists(atPath: entry) else {
            Self.nodeStarted = false
            result(0)
            return
        }

        setenv("PORT", String(port), 1)
        setenv("DEV_HTTP_PORT", String(port), 1)
        setenv("DART_PORT", String(dartPort), 1)
        setenv("NODE_PATH", nodeDir, 1)
        setenv("TVS_PARENT_PID", String(ProcessInfo.processInfo.processIdentifier), 1)
        // BUNDLE_PATH 不在这里设置：模板里的 __TVS_BUNDLE_PATH__ 已由 Dart 侧替换。

        // node_start 阻塞 → 后台线程
        let thread = Thread {
            NSLog("[TVS-NodeBridge] starting node: \(entry)")
            let code = Self.runNode(entry: entry)
            NSLog("[TVS-NodeBridge] node exited with code \(code)")
            Self.nodeStarted = false
        }
        thread.stackSize = 2 * 1024 * 1024
        thread.start()

        // 等端口起来再回报，避免 Dart 侧拿到端口却立刻调 API 失败
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(Self.startupTimeout)
            while Date() < deadline {
                if self.isPortOpen() {
                    DispatchQueue.main.async { result(self.port) }
                    return
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
            Self.nodeStarted = false
            DispatchQueue.main.async { result(0) }
        }
    }

    /// 把 Swift 的字符串数组转成 `node_start` 需要的 C argv。
    private static func runNode(entry: String) -> Int32 {
        let arguments = ["node", entry]
        var cargs: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        defer {
            for pointer in cargs {
                free(pointer)
            }
        }
        return cargs.withUnsafeMutableBufferPointer { buffer in
            node_start(Int32(buffer.count), buffer.baseAddress)
        }
    }

    // MARK: - 工具

    private func isPortOpen() -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        if socketDescriptor < 0 { return false }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
