import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  private var statusMenuItem: NSMenuItem?
  private var trayChannel: FlutterMethodChannel?
  private var allowForceClose: Bool = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: 1200, height: 800)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 960, height: 640)
    self.title = "POS Print Agent — ระบบจัดการเครื่องพิมพ์ใบเสร็จ"
    self.delegate = self

    let channel = FlutterMethodChannel(
      name: "com.pos.printagent/tray",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.trayChannel = channel

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "initTray":
        let args = call.arguments as? [String: Any]
        let status = (args?["status"] as? String) ?? "สถานะ: พร้อมใช้งาน (127.0.0.1:8765)"
        self.setupStatusBar(statusText: status)
        result(true)
      case "updateTrayStatus":
        let args = call.arguments as? [String: Any]
        if let status = args?["status"] as? String {
          self.statusMenuItem?.title = status
        }
        result(true)
      case "hideWindow":
        self.orderOut(nil)
        result(true)
      case "showWindow":
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        result(true)
      case "terminateApp":
        self.allowForceClose = true
        NSApp.terminate(nil)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  private func setupStatusBar(statusText: String) {
    if self.statusItem != nil {
      self.statusMenuItem?.title = statusText
      return
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "🖨️ POS Print"

    let menu = NSMenu()
    let statusItemNode = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
    statusItemNode.isEnabled = false
    self.statusMenuItem = statusItemNode
    menu.addItem(statusItemNode)
    menu.addItem(NSMenuItem.separator())

    let openItem = NSMenuItem(
      title: "เปิดหน้าต่างหลัก POS Print Agent",
      action: #selector(handleShowWindow),
      keyEquivalent: "o"
    )
    openItem.target = self
    menu.addItem(openItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "ออกจากโปรแกรมอย่างปลอดภัย (Quit)",
      action: #selector(handleQuitApp),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)

    item.menu = menu
    self.statusItem = item
  }

  @objc private func handleShowWindow() {
    self.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.trayChannel?.invokeMethod("onTrayShowWindow", arguments: nil)
  }

  @objc private func handleQuitApp() {
    self.trayChannel?.invokeMethod("onTrayQuitApp", arguments: nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if self.allowForceClose {
      return true
    }
    // Hide window to menu bar instead of closing so Local HTTP API keeps running
    self.orderOut(nil)
    return false
  }
}
