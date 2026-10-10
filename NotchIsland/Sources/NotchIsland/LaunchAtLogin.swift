import AppKit
import ServiceManagement

/// Wraps `SMAppService.mainApp`, the system's login-item registration for this app.
///
/// The system is the source of truth (the person can also change it in System Settings), so the
/// status is re-read whenever the customizer appears or the app becomes active again.
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool { status == .enabled }

    /// A one-line explanation for states the toggle alone can't express.
    var note: String {
        if let errorMessage { return errorMessage }
        switch status {
        case .requiresApproval:
            return "Approve Goosenotch in System Settings › General › Login Items."
        case .notFound:
            return "Move Goosenotch to your Applications folder to enable this."
        default:
            return ""
        }
    }

    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Couldn't change the login item. \(error.localizedDescription)"
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
