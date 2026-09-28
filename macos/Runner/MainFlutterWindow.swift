import Cocoa
import FlutterMacOS

/// TVS macOS 主窗口。
///
/// 官方 dmg 构建流程：`flutter build macos --release` 后由
/// `flutter build macos` 的 macos/Runner.xcodeproj 产出 .app，
/// 再打成 .dmg 分发（GitHub release 中的 tvs-*.dmg）。
///
/// 与 iOS 版的差异：
///   - macOS 上 Node.js 以受签名校验的子进程方式运行（而不是内嵌
///     NodeMobile.framework），bootstrap 模板里 TVS_PARENT_PID
///     看门狗在 500ms 轮询检测父进程存活，父进程消失即退出。
class MainFlutterWindow: FlutterWindow {
    private let nodeBridge: NodeBridge?

    override init(flutterViewController: FlutterViewController) {
        nodeBridge = NodeBridge()
        nodeBridge?.register(registrar: flutterViewController.registrar(
            forPlugin: "com.example.tvs.nodebridge")!,
            documentDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask)[0])
        super.init(flutterViewController: flutterViewController)
    }

    override func windowDidLoad() {
        super.windowDidLoad()

        // TVS 支持手机、平板与 macOS 多形态，窗口尺寸自适应。
        let screen = NSScreen.main?.frame ?? .zero
        let contentSize = NSSize(width: min(1280, screen.width - 32),
                                 height: min(800, screen.height - 64))
        if let contentRect = contentWindow?.contentRect(forFrameRect: .zero) {
            contentWindow?.setFrame(
                NSRect(x: contentRect.origin.x,
                       y: contentRect.origin.y,
                       width: contentSize.width,
                       height: contentSize.height),
                display: true)
        }
    }

    override var acceptsFirstResponder: Bool {
        return false
    }
}
