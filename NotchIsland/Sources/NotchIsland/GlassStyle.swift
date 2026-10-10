import AppKit
import SwiftUI

/// Muted, cool-leaning tones that share one softness (similar lightness, low saturation), so
/// each tab is recognisable without anything competing for attention on the dark island.
enum IslandPalette {
    /// Dusty sky blue.
    static let timer = Color(red: 0.55, green: 0.72, blue: 0.88)
    /// Soft periwinkle.
    static let assistant = Color(red: 0.69, green: 0.67, blue: 0.90)
    /// Muted rose. Replaced by the artwork's colour while a track with artwork is playing.
    static let music = Color(red: 0.88, green: 0.64, blue: 0.72)
    /// Soft terracotta; warm so recording reads as "live" without being alarming.
    static let recorder = Color(red: 0.90, green: 0.62, blue: 0.56)
    /// Sage mint.
    static let calendar = Color(red: 0.56, green: 0.80, blue: 0.71)
    /// Cool slate blue for system accents: caret, selection, focus rings, sliders.
    static let accent = Color(red: 0.62, green: 0.75, blue: 0.92)
    /// Cool slate for the optional glass tint.
    static let neutralTint = Color(red: 0.58, green: 0.65, blue: 0.76)
}

/// A 4-pt spacing scale so every panel breathes the same way.
enum IslandSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
}

/// Shared motion, so the notch, its content and the controls all feel like one material.
enum IslandMotion {
    /// Opening has a touch of overshoot, like the island swelling out of the notch.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Closing settles without bounce so it never rebounds past the notch.
    static let close = Animation.spring(response: 0.34, dampingFraction: 0.94)
    static let tab = Animation.smooth(duration: 0.3)
    static let press = Animation.spring(response: 0.26, dampingFraction: 0.7)
    static let hover = Animation.easeOut(duration: 0.16)
}

extension GlassBlur {
    /// Each level is a visibly different frosting, so the setting is always perceptible.
    var material: Material? {
        switch self {
        case .clear: nil
        case .subtle: .ultraThinMaterial
        case .balanced: .thinMaterial
        case .strong: .regularMaterial
        case .maximum: .ultraThickMaterial
        }
    }
}

extension View {
    func islandGlass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        tintStrength: Double = 0.7,
        clear: Bool = false,
        blur: GlassBlur = .balanced,
        refraction: Bool = false
    ) -> some View {
        background {
            ZStack {
                if let material = blur.material { shape.fill(material) }
                if clear { shape.fill(Color.white.opacity(0.05)) }
                if let tint { shape.fill(tint.opacity(0.2 * tintStrength)) }
            }
        }
        .overlay {
            Group {
                if refraction, #available(macOS 26.0, *) {
                    // "Clear" and "Subtle" keep the see-through lens; stronger levels use the frosted one.
                    shape.fill(Color.white.opacity(0.001))
                        .glassEffect(blur == .clear || blur == .subtle ? .clear : .regular, in: shape)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay {
            // Specular edge: bright where light would catch the top-leading corner, fading away
            // across the glass, with a faint return along the bottom edge.
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.22), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.45),
                        .init(color: .white.opacity(0.11), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
            .allowsHitTesting(false)
        }
    }

    /// Glass for small controls. On macOS 26 this is real, interactive Liquid Glass with
    /// refraction; earlier systems get the layered material fallback.
    @ViewBuilder
    func controlGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint.opacity(0.28)).interactive(), in: shape)
            } else {
                self.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            self.islandGlass(shape, tint: tint)
        }
    }

    /// Soft highlight while the pointer is over a control.
    func hoverHighlight<S: Shape>(_ shape: S) -> some View {
        modifier(HoverHighlight(shape: shape))
    }
}

private struct HoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                shape.fill(Color.white.opacity(hovering ? 0.10 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                withAnimation(IslandMotion.hover) { hovering = inside }
            }
    }
}

/// Springy press feedback shared by every glass control.
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(IslandMotion.press, value: configuration.isPressed)
    }
}

struct GlassIconButton: View {
    let systemName: String
    var label: String
    var size: CGFloat = 40
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle())
        .controlGlass(Circle(), tint: tint)
        .hoverHighlight(Circle())
        .accessibilityLabel(label)
        .help(label)
    }
}

struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    var tint: Color = IslandPalette.assistant
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
                if !title.isEmpty {
                    Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.white.opacity(isDisabled ? 0.4 : 1))
            .padding(.horizontal, title.isEmpty ? 11 : 12)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .disabled(isDisabled)
        .controlGlass(Capsule(), tint: isSelected ? tint : nil)
        .hoverHighlight(Capsule())
        .animation(IslandMotion.hover, value: isSelected)
    }
}
