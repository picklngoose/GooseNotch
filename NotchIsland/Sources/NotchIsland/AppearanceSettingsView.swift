import AppKit
import SwiftUI

enum GlassBlur: String, CaseIterable, Hashable, Identifiable {
    /// No frosting at all: just the clear Liquid Glass lens, as see-through as it gets.
    case clear
    case subtle
    case balanced
    case strong
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "Clear"
        case .subtle: "Subtle"
        case .balanced: "Balanced"
        case .strong: "Strong"
        case .maximum: "Maximum"
        }
    }

}

enum IslandStyle: String, CaseIterable, Hashable, Identifiable {
    case solidBlack
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solidBlack: "Solid Black"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

@MainActor
final class IslandAppearance: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Solid black matches the notch exactly; Liquid Glass fades from black into frosted glass.
    @Published var style: IslandStyle {
        didSet { defaults.set(style.rawValue, forKey: "islandStyle") }
    }
    /// Show a countdown beside the closed notch when an event is about to start.
    @Published var showEventAlerts: Bool {
        didSet { defaults.set(showEventAlerts, forKey: "islandShowEventAlerts") }
    }
    /// How much of the frosted glass shows through (0 hides it, 1 is fully frosted).
    @Published var glassDensity: Double {
        didSet { defaults.set(glassDensity, forKey: "islandGlassDensity") }
    }
    /// How quickly the black fades out toward the bottom (0 stays mostly black, 1 reveals the glass).
    @Published var fade: Double {
        didSet { defaults.set(fade, forKey: "islandFade") }
    }

    @Published var opacity: Double {
        didSet { defaults.set(opacity, forKey: "islandOpacity") }
    }
    @Published var blur: GlassBlur {
        didSet { defaults.set(blur.rawValue, forKey: "islandGlassBlur") }
    }
    @Published var expandedWidth: Double {
        didSet { defaults.set(expandedWidth, forKey: "islandExpandedWidth") }
    }
    @Published var cornerRadius: Double {
        didSet { defaults.set(cornerRadius, forKey: "islandCornerRadius") }
    }
    @Published var activityWingWidth: Double {
        didSet { defaults.set(activityWingWidth, forKey: "islandActivityWingWidth") }
    }
    @Published var rimStrength: Double {
        didSet { defaults.set(rimStrength, forKey: "islandRimStrength") }
    }
    @Published var tintStrength: Double {
        didSet { defaults.set(tintStrength, forKey: "islandTintStrength") }
    }
    var tintColor: Color { IslandPalette.neutralTint }

    init() {
        let defaults = UserDefaults.standard
        func storedValue(_ key: String, default fallback: Double, range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }

        style = IslandStyle(rawValue: defaults.string(forKey: "islandStyle") ?? "") ?? .liquidGlass
        showEventAlerts = defaults.object(forKey: "islandShowEventAlerts") as? Bool ?? true
        glassDensity = storedValue("islandGlassDensity", default: 0.9, range: 0...1)
        fade = storedValue("islandFade", default: 0.6, range: 0...1)
        opacity = storedValue("islandOpacity", default: 1, range: 0...1)
        blur = GlassBlur(rawValue: defaults.string(forKey: "islandGlassBlur") ?? "") ?? .balanced
        expandedWidth = storedValue(
            "islandExpandedWidth",
            default: Double(IslandMetrics.expandedSize.width),
            range: 480...Double(IslandMetrics.expandedSize.width)
        )
        cornerRadius = storedValue(
            "islandCornerRadius",
            default: Double(IslandMetrics.contentCornerRadius),
            range: 16...44
        )
        activityWingWidth = storedValue(
            "islandActivityWingWidth",
            default: Double(IslandMetrics.activityWingWidth),
            range: 40...100
        )
        rimStrength = storedValue("islandRimStrength", default: 1, range: 0...1)
        tintStrength = storedValue("islandTintStrength", default: 0, range: 0...0.8)
    }

    func resetToDefaults() {
        style = .liquidGlass
        showEventAlerts = true
        glassDensity = 0.9
        fade = 0.6
        opacity = 1
        blur = .balanced
        expandedWidth = Double(IslandMetrics.expandedSize.width)
        cornerRadius = Double(IslandMetrics.contentCornerRadius)
        activityWingWidth = Double(IslandMetrics.activityWingWidth)
        rimStrength = 1
        tintStrength = 0
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var appearance: IslandAppearance
    @StateObject private var launchAtLogin = LaunchAtLogin()
    @AppStorage("timerNotifications") private var timerNotifications = true
    @AppStorage("timerChime") private var timerChime = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                // Always reserves two lines so the window doesn't need to resize.
                HStack(alignment: .top) {
                    Text(launchAtLogin.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if launchAtLogin.needsApproval {
                        Button("Open Settings") { launchAtLogin.openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                }
                .frame(height: 30, alignment: .topLeading)

                Toggle("Show upcoming events in the notch", isOn: $appearance.showEventAlerts)
                Toggle("Notify when a timer finishes", isOn: $timerNotifications)
                Toggle("Play a chime when a timer finishes", isOn: $timerChime)
            }

            Section("Style") {
                Picker("Island", selection: $appearance.style.animation(.smooth(duration: 0.3))) {
                    ForEach(IslandStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                settingSlider("Island opacity", value: $appearance.opacity, range: 0...1)
            }

            // Stays in place (just dimmed) in Solid Black so the window never changes size.
            Section("Liquid Glass") {
                Picker("Blur", selection: $appearance.blur) {
                    ForEach(GlassBlur.allCases) { blur in
                        Text(blur.title).tag(blur)
                    }
                }
                settingSlider("Glass density", value: $appearance.glassDensity, range: 0...1)
                settingSlider("Black fade-out", value: $appearance.fade, range: 0...1)
                settingSlider("Glass tint", value: $appearance.tintStrength, range: 0...0.8)
            }
            .disabled(appearance.style == .solidBlack)
            .opacity(appearance.style == .solidBlack ? 0.45 : 1)

            Section("Shape and detail") {
                settingSlider(
                    "Expanded width",
                    value: $appearance.expandedWidth,
                    range: 480...Double(IslandMetrics.expandedSize.width),
                    unit: " pt",
                    multiplier: 1
                )
                settingSlider(
                    "Expanded corner radius",
                    value: $appearance.cornerRadius,
                    range: 16...44,
                    unit: " pt",
                    multiplier: 1
                )
                settingSlider(
                    "Activity wing width",
                    value: $appearance.activityWingWidth,
                    range: 40...100,
                    unit: " pt",
                    multiplier: 1
                )
                settingSlider("Glass rim", value: $appearance.rimStrength, range: 0...1)
                Button("Reset to Defaults", role: .destructive) {
                    appearance.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .preferredColorScheme(.dark)
        .tint(IslandPalette.accent)
        .padding(20)
        .frame(width: 390)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func settingSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String = "%",
        multiplier: Double = 100
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * multiplier).rounded()))\(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

@MainActor
final class AppearanceSettingsWindowController {
    private let window: NSWindow
    private var observers: [NSObjectProtocol] = []

    /// Called with `true` while the window is on screen. The island stays open for exactly that
    /// long, so changes can be judged on the real thing.
    var onVisibilityChange: ((Bool) -> Void)?

    init(appearance: IslandAppearance) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notch Appearance"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppearanceSettingsView(appearance: appearance))
        window.contentMinSize = NSSize(width: 430, height: 320)
        window.isMovableByWindowBackground = true

        let center = NotificationCenter.default
        let hide: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.onVisibilityChange?(false) }
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: hide))
        observers.append(center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: window, queue: .main, using: hide))
        observers.append(center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onVisibilityChange?(true) }
        })
    }

    /// The island floats above normal windows and stays open while this window is up, so the
    /// window has to sit entirely below it (and fit on screen), or its title bar is unreachable.
    private func positionBelowIsland() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens.first
        else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - IslandMetrics.windowSize.height - 12
        let available = max(islandBottom - visible.minY - 8, 320)

        var frame = window.frame
        frame.size.height = min(frame.height, available)
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = islandBottom - frame.height
        window.setFrame(frame, display: false)
    }

    func show() {
        // Only on first appearance, so a window the person moved stays where they put it.
        if !window.isVisible { positionBelowIsland() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
    }
}
