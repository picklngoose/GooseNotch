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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = IslandController()
        controller.start()
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

}
