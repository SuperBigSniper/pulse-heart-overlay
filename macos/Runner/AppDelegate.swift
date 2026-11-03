import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 返回 false：角落模式切换会程序化 orderOut 唯一窗口，若这里返回 true
  // AppKit 会判定“最后一个窗口已关闭”而直接终止整个应用。
  // 代价是点关闭按钮只隐藏窗口不退出，退出请用 Cmd+Q；
  // 点 Dock 图标时由 applicationShouldHandleReopen 把窗口拉回来。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      if let mainWindow = sender.windows.first(where: { $0 is MainFlutterWindow }) {
        mainWindow.makeKeyAndOrderFront(nil)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
