import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // G-02-B：播放器插件（非插件工程手动注册，与 Android MainActivity 同模式）。
    if let registrar = flutterViewController.registrar(forPlugin: "PlayerPlugin") {
      PlayerPlugin.register(with: registrar)
    }

    super.awakeFromNib()
  }
}
