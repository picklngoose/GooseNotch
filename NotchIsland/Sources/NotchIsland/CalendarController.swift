import AppKit
import EventKit
import SwiftUI

/// A value-type snapshot of an `EKEvent`, so the UI never holds on to EventKit objects.
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarTitle: String
    let calendarColor: NSColor
    let joinURL: URL?

    func isOngoing(at date: Date) -> Bool {
        !isAllDay && start <= date && date < end
    }
}

/// Reads upcoming events through EventKit.
///
/// Nothing is requested at launch: the system permission prompt only appears when the person
/// presses "Connect Calendar" in the Calendar tab. Authorization is re-checked whenever the island
/// opens, the app becomes active (e.g. after toggling access in System Settings) or the event
/// store changes.
@MainActor
final class CalendarController: ObservableObject {
    enum Access: Equatable {
        case notDetermined
        case authorized
        case writeOnly
        case denied
        case restricted
    }

    @Published private(set) var access: Access
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?
    @Published var selectedID: String?
    /// The next timed event, only while it starts within `soonWindow`. Drives the notch indicator.
    @Published private(set) var soonEvent: CalendarEvent?

    /// How early the notch starts counting down to an event.
    static let soonWindow: TimeInterval = 10 * 60

    /// How far ahead the agenda looks.
    private let horizonDays = 7
    private let maxEvents = 30

    private let store = EKEventStore()
    private var observers: [NSObjectProtocol] = []
    private var ticker: Timer?
    private var soonTicker: Timer?

    init() {
        access = Self.currentAccess()
    }

    // MARK: Derived

    /// The first timed event that is ongoing or still to come.
    var nextEvent: CalendarEvent? {
        events.first { !$0.isAllDay }
    }

    /// The event shown in the detail card: the one the person picked, else the next one.
    var focusedEvent: CalendarEvent? {
        if let selectedID, let match = events.first(where: { $0.id == selectedID }) { return match }
        return nextEvent ?? events.first
    }

    // MARK: Lifecycle

    func start() {
        guard ticker == nil else { return }

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })

        // Rolls finished events off the list and picks up the next day without any user action.
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Cheap (filters the cached list), so it can run every second and the indicator appears and
        // disappears on time without re-querying EventKit.
        soonTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSoon() }
        }
        refresh()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        soonTicker?.invalidate()
        soonTicker = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: Permission

    func requestAccess() {
        guard access == .notDetermined, !isRequesting else { return }
        isRequesting = true
        errorMessage = nil
        // An accessory (menu-bar style) app has to be frontmost for the system prompt to appear.
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            do {
                _ = try await store.requestFullAccessToEvents()
            } catch {
                errorMessage = "Couldn't ask for calendar access. \(error.localizedDescription)"
            }
            isRequesting = false
            refresh()
        }
    }

    func openPrivacySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            errorMessage = "Couldn't find the Calendar app."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: Loading

    func refresh() {
        let current = Self.currentAccess()
        if current != access { access = current }

        guard current == .authorized else {
            if !events.isEmpty { events = [] }
            updateSoon()
            return
        }

        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: horizonDays, to: now)
            ?? now.addingTimeInterval(TimeInterval(horizonDays) * 86_400)
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)

        let loaded: [CalendarEvent] = store.events(matching: predicate)
            .filter { $0.status != .canceled && !Self.isDeclined($0) }
            .compactMap(Self.snapshot)
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let trimmed = Array(loaded.prefix(maxEvents))
        if trimmed != events { events = trimmed }
        errorMessage = nil
        if let selectedID, !trimmed.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        updateSoon()
    }

    private func updateSoon() {
        let now = Date()
        var soon: CalendarEvent?
        if access == .authorized,
           let next = events.first(where: { !$0.isAllDay && $0.start > now }),
           next.start.timeIntervalSince(now) <= Self.soonWindow {
            soon = next
        }
        if soon != soonEvent { soonEvent = soon }
    }

    // MARK: Helpers

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .writeOnly: return .writeOnly
        case .fullAccess: return .authorized
        default: return .authorized // legacy `.authorized` from before macOS 14
        }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
    }

    private static func snapshot(_ event: EKEvent) -> CalendarEvent? {
        guard let start = event.startDate, let end = event.endDate else { return nil }

        // Recurring events share one identifier across occurrences, so add the start time.
        let base = event.eventIdentifier ?? UUID().uuidString
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (event.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let color = event.calendar.flatMap { NSColor(cgColor: $0.cgColor) } ?? .systemGray

        return CalendarEvent(
            id: "\(base)@\(start.timeIntervalSince1970)",
            title: title.isEmpty ? "Untitled Event" : title,
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes,
            calendarTitle: event.calendar?.title ?? "Calendar",
            calendarColor: color,
            joinURL: joinLink(for: event, location: location, notes: notes)
        )
    }

    /// Finds a video-call link in the event's URL, location or notes.
    private static func joinLink(for event: EKEvent, location: String, notes: String) -> URL? {
        let hosts = [
            "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
            "webex.com", "facetime.apple.com", "whereby.com", "gotomeeting.com"
        ]
        func isCall(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        var candidates: [URL] = []
        if let url = event.url { candidates.append(url) }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for text in [location, notes] where !text.isEmpty {
                let range = NSRange(text.startIndex..., in: text)
                detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    if let url = match?.url { candidates.append(url) }
                }
            }
        }
        return candidates.first(where: isCall)
    }
}

// MARK: - Formatting

enum CalendarFormat {
    struct Countdown: Equatable {
        let label: String
        let value: String
    }

    private static let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    static func timeRange(for event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        return intervalFormatter.string(from: event.start, to: event.end)
    }

    static func dayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return dayFormatter.string(from: date)
    }

    static func countdown(for event: CalendarEvent, now: Date) -> Countdown {
        let calendar = Calendar.current
        if event.isAllDay {
            let day = calendar.startOfDay(for: max(event.start, now))
            let value = calendar.isDateInToday(day) ? "Today" : weekdayFormatter.string(from: day)
            return Countdown(label: "All day", value: value)
        }
        if event.isOngoing(at: now) {
            return Countdown(label: "Now · ends in", value: remaining(event.end.timeIntervalSince(now)))
        }
        return Countdown(label: "Starts in", value: remaining(event.start.timeIntervalSince(now)))
    }

    /// m:ss, for the compact countdown beside the notch.
    static func shortCountdown(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.up)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 12:05 under an hour, 2h 05m under a day, then 3d 4h.
    private static func remaining(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.up)), 0)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
