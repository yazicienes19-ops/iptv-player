import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Groß genug für das 3-Spalten-Layout; schmaler wird automatisch das Handy-Layout.
    let size = NSSize(width: 1440, height: 900)
    let screen = NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: size)
    let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
    self.setFrame(NSRect(origin: origin, size: size), display: true)
    self.minSize = NSSize(width: 380, height: 560)
    self.title = "IpFlix"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
