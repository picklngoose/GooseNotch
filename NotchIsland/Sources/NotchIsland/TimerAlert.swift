import AppKit
import UserNotifications

/// Chime and notification for a finished countdown.
///
/// Notification permission is requested the first time a countdown is started, so the prompt
/// appears in context instead of at launch. If it's declined the chime still plays.
@MainActor
final class TimerAlert: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TimerAlert()

    /// Both default to on; the customizer writes these keys.
    static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "timerNotifications") as? Bool ?? true
    }
    static var chimeEnabled: Bool {
        UserDefaults.standard.object(forKey: "timerChime") as? Bool ?? true
    }

    private var didSetUp = false

    /// `UNUserNotificationCenter` traps when the process isn't an app bundle (e.g. `swift run`).
    private func center() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        if !didSetUp {
            center.delegate = self
            didSetUp = true
        }
        return center
    }

    /// Call when a countdown starts: asks for permission once, and only if it's still undecided.
    func prepare() {
        guard Self.notificationsEnabled, let center = center() else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    func timerFinished(duration: TimeInterval) {
        if Self.chimeEnabled { NSSound(named: NSSound.Name("Glass"))?.play() }
        guard Self.notificationsEnabled, let center = center() else { return }

        let body = Self.describe(duration) + " is up."
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional: break
            default: return
            }
            let content = UNMutableNotificationContent()
            content.title = "Timer finished"
            content.body = body
            content.threadIdentifier = "goosenotch.timer"
            let request = UNNotificationRequest(
                identifier: "goosenotch.timer.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request) { _ in }
        }
    }

    // Show the banner even though this app counts as frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    private nonisolated static func describe(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if seconds > 0 && hours == 0 { parts.append("\(seconds) sec") }
        return parts.isEmpty ? "Your timer" : parts.joined(separator: " ") + " timer"
    }
}
