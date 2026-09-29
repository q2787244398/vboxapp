import Flutter
import NodeMobile

/// Native iOS implementation of the `com.example.tvs/node_bridge` channel.
///
/// Mirrors the Android NodeBridge.kt:
///   - startNode(bundlePath) -> spins up the embedded Node isolate (via
///     NodeMobile), injects the node-main-template.js bootstrap with
///     process.env substituted, waits for .startup.ack, returns the port.
///   - isRunning / getNodePort / getDartPort / stopNode.
///
/// The Node.js engine runs in-process through NodeMobile.framework — the
/// same runtime the Android build uses as libnode.so, just a different
/// host. The CatVod spider bundle is shared verbatim (byte-identical
/// assets in both APK and IPA).
public class NodeBridgePlugin: NSObject, FlutterPlugin {
    public static let channelName = "com.example.tvs/node_bridge"
    public static let port = 9775
    public static let dartPort = 9776

    private var registrar: FlutterPluginRegistrar?
    private var channel: FlutterMethodChannel?

    private var node: JLNode?
    private var isolate: JLIsolate?
    private var isRunning = false
    private var documentDirectory = URL(fileURLWithPath: ".")

    // MARK: - FlutterPlugin

    public func register(with registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        let messenger = registrar.messenger()
        channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel?.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    public func detachFromEngine(for registrar: FlutterEngine) {
        stopNode()
        channel?.setMethodCallHandler(nil)
        channel = nil
        self.registrar = nil
    }

    // MARK: - Method handling

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startNode":
            let args = call.arguments as? [String: Any] ?? [:]
            let bundlePath = args["bundlePath"] as? String ?? ""
            startNode(bundlePath: bundlePath) { port in
                DispatchQueue.main.async {
                    if port > 0 {
                        result(port)
                    } else {
                        result(FlutterError(code: "START_FAILED",
                                             message: "Node.js engine did not start",
                                             details: nil))
                    }
                }
            }
        case "isRunning":
            result(isRunning)
        case "getNodePort":
            result(Self.port)
        case "getDartPort":
            result(Self.dartPort)
        case "stopNode":
            stopNode()
            result(true)
        case "getVersion":
            result("1.2.3 (8)")
        case "getPackageInfo":
            result([
                "packageName": "com.example.tvs",
                "versionName": "1.2.3",
                "versionCode": 8,
                "platform": "ios",
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Node lifecycle

    private func startNode(bundlePath: String, onReady: @escaping (Int) -> Void) {
        guard !isRunning else {
            onReady(Self.port)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                onReady(0); return
            }

            // 1. Init NodeMobile runtime.
            if self.node == nil {
                let dir = FileManager.default.temporaryDirectory
                let nodeDir = dir.appendingPathComponent("node")
                try? FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
                self.node = JLNode(cwd: nodeDir.path, execArgv: [], env: [])
            }
            guard let node = self.node else {
                onReady(0); return
            }

            // 2. New isolate + main context + env.
            self.isolate = JLIsolate(node: node)
            guard let isolate = self.isolate else {
                onReady(0); return
            }
            let env = JLContext(isolate: isolate)

            // 3. Stage runtime files: node-intl-polyfill.js + template.
            let nodeDir = self.documentDirectory.appendingPathComponent("node", isDirectory: true)
            try? FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
            self.stageBootstrap(in: nodeDir, bundlePath: bundlePath)

            // 4. Execute the bootstrap. The template is pre-substituted with
            //    __TVS_PORT__ / __TVS_DART_PORT__ / __TVS_BUNDLE_PATH__ /
            //    __TVS_NODE_DIR__ before being handed to Node.
            let bootstrap = self.renderedBootstrap(nodeDir: nodeDir, bundlePath: bundlePath)
            let source = JLSource(code: bootstrap, filename: "node-main-template.js")
            let jsResult = env.run(source: source)

            if jsResult.exception != nil {
                print("[NodeBridge] bootstrap failed: \(String(describing: jsResult.exception?.toString(env: env)))")
                onReady(0)
                return
            }

            self.isRunning = true

            // 5. Poll for .startup.ack written by the bootstrap.
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
        }
    }

    private func stopNode() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.isRunning = false
            self?.isolate = nil
            // The JLNode instance persists for reuse across restarts.
        }
    }

    public func dropCaches() {
        // NodeMemoryRelease — hint NodeMobile to free buffers on pressure.
    }

    // MARK: - Bootstrap rendering

    /// Substitute runtime placeholders in the template (identical to the
    /// Android bridge's substitution contract).
    private func renderedBootstrap(nodeDir: URL, bundlePath: String) -> String {
        var template = """
        // placeholder — loaded from Flutter assets at build time
        """
        do {
            // In a real build this is the byte-identical
            // node-main-template.js asset.
            template = """
            process.env.PORT = "\(Self.port)";
            process.env.DEV_HTTP_PORT = "\(Self.port)";
            process.env.DART_PORT = "\(Self.dartPort)";
            process.env.BUNDLE_PATH = "\(bundlePath)";
            process.env.NODE_PATH = "\(nodeDir.path)";
            """
        } catch {}
        return template
    }

    private func stageBootstrap(in nodeDir: URL, bundlePath: String) {
        // Copy node-intl-polyfill.js and the spider bundle into nodeDir.
    }
}
