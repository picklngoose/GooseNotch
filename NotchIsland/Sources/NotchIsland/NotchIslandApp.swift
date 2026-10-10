import AppKit
import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = IslandController()
        controller.start()
        self.controller = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.makeGooseIcon()
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch Memos Folder", action: #selector(openMemos), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Goosenotch", action: #selector(quit), keyEquivalent: "q")
            .target = self
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    @objc private func openMemos() { controller?.openMemosFolder() }
    @objc private func quit() { NSApp.terminate(nil) }

    private static func makeGooseIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3, y: 1))
            path.curve(to: NSPoint(x: 8, y: 7), controlPoint1: NSPoint(x: 3, y: 4), controlPoint2: NSPoint(x: 5, y: 6))
            path.curve(to: NSPoint(x: 8, y: 11), controlPoint1: NSPoint(x: 10, y: 8), controlPoint2: NSPoint(x: 10, y: 10))
            path.curve(to: NSPoint(x: 10, y: 14), controlPoint1: NSPoint(x: 7, y: 13), controlPoint2: NSPoint(x: 7, y: 16))
            path.curve(to: NSPoint(x: 13, y: 15), controlPoint1: NSPoint(x: 10, y: 16), controlPoint2: NSPoint(x: 12, y: 16))
            path.line(to: NSPoint(x: 17, y: 13))
            path.line(to: NSPoint(x: 13, y: 12))
            path.curve(to: NSPoint(x: 11, y: 8), controlPoint1: NSPoint(x: 13, y: 10), controlPoint2: NSPoint(x: 13, y: 9))
            path.curve(to: NSPoint(x: 8, y: 6), controlPoint1: NSPoint(x: 10, y: 7), controlPoint2: NSPoint(x: 9, y: 6))
            path.curve(to: NSPoint(x: 3, y: 1), controlPoint1: NSPoint(x: 6, y: 4), controlPoint2: NSPoint(x: 4, y: 2))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
