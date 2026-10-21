import Cocoa
import FlutterMacOS
import desktop_multi_window
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // Audio plugins on the lyrics engine crash the process when that
      // window is destroyed. Window chrome is the only native piece it needs.
      WindowManagerPlugin.register(with: controller.registrar(forPlugin: "WindowManagerPlugin"))
      controller.backgroundColor = NSColor.clear
      controller.view.window?.isOpaque = false
      controller.view.window?.backgroundColor = NSColor.clear
    }

    super.awakeFromNib()
  }
}
