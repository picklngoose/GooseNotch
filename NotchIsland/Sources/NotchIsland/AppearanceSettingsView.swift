import AppKit
import SwiftUI

enum GlassBlur: String, CaseIterable, Hashable, Identifiable {
    case subtle
    case balanced
    case strong
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: "Subtle"
        case .balanced: "Balanced"
        case .strong: "Strong"
        case .maximum: "Maximum"
        }
    }

    var material: Material {
        switch self {
        case .subtle: .ultraThinMaterial
        case .balanced: .ultraThinMaterial
        case .strong: .regularMaterial
        case .maximum: .thickMaterial
        }
    }

    var tintBoost: Double {
        switch self {
        case .subtle, .balanced: 0
        case .strong: 0.12
        case .maximum: 0.24
        }
    }
}

@MainActor
final class IslandAppearance: ObservableObject {
    private let defaults = UserDefaults.standard

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
    var tintColor: Color { Color(white: 0.72) }

    init() {
        let defaults = UserDefaults.standard
        func storedValue(_ key: String, default fallback: Double, range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }

        opacity = storedValue("islandOpacity", default: 1, range: 0...1)
        blur = GlassBlur(rawValue: defaults.string(forKey: "islandGlassBlur") ?? "") ?? .subtle
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
        opacity = 1
        blur = .subtle
        expandedWidth = Double(IslandMetrics.expandedSize.width)
        cornerRadius = Double(IslandMetrics.contentCornerRadius)
        activityWingWidth = Double(IslandMetrics.activityWingWidth)
        rimStrength = 1
        tintStrength = 0
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var appearance: IslandAppearance

    var body: some View {
        Form {
            Section("Glass") {
                Picker("Blur", selection: $appearance.blur) {
                    ForEach(GlassBlur.allCases) { blur in
                        Text(blur.title).tag(blur)
                    }
                }
                settingSlider("Neutral tint", value: $appearance.tintStrength, range: 0...0.8)
                settingSlider("Island opacity", value: $appearance.opacity, range: 0...1)
            }

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
        .preferredColorScheme(.dark)
        .tint(Color(white: 0.78))
        .padding(20)
        .frame(width: 390)
        .fixedSize(horizontal: false, vertical: true)
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

    init(appearance: IslandAppearance) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 530),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notch Appearance"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppearanceSettingsView(appearance: appearance))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
