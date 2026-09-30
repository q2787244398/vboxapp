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
    // Flutter 3.47.5+ 起 registrar(forPlugin:) 返回非可选 any FlutterPluginRegistrar，直接取值。
    let registrar = flutterViewController.registrar(forPlugin: "PlayerPlugin")
    PlayerPlugin.register(with: registrar)

    super.awakeFromNib()
  }
}
