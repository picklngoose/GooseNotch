import SwiftUI

enum IslandPalette {
    static let timer = Color(white: 0.78)
    static let assistant = Color(white: 0.94)
    static let music = Color(white: 0.86)
    static let recorder = Color(white: 0.64)
}

// MARK: - Liquid Glass helpers
//
// On macOS 26+ these use the real Liquid Glass APIs (glassEffect / GlassEffectContainer).
// On macOS 14–15 they fall back to system materials so the app still looks native.

@available(macOS 26.0, *)
private func makeIslandGlass(
    tint: Color?,
    tintStrength: Double,
    clear: Bool,
    blur: GlassBlur
) -> Glass {
    var glass = clear || blur == .subtle ? Glass.clear : Glass.regular
    if let tint {
        glass = glass.tint(tint.opacity(min(tintStrength + blur.tintBoost, 1)))
    } else if blur.tintBoost > 0 {
        glass = glass.tint(.white.opacity(blur.tintBoost))
    }
    return glass
}

extension View {
    @ViewBuilder
    func islandGlass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        tintStrength: Double = 0.7,
        clear: Bool = false,
        blur: GlassBlur = .balanced
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                makeIslandGlass(
                    tint: tint,
                    tintStrength: tintStrength,
                    clear: clear,
                    blur: blur
                ),
                in: shape
            )
        } else {
            self.background {
                shape.fill(clear ? AnyShapeStyle(Color.white.opacity(0.05)) : AnyShapeStyle(blur.material))
                if let tint { shape.fill(tint.opacity(0.2 * tintStrength)) }
            }
            .overlay { shape.stroke(.white.opacity(0.08), lineWidth: 0.5) }
        }
    }
}

/// Groups nearby glass elements so they blend and morph together (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
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
        .buttonStyle(.plain)
        .islandGlass(Circle(), tint: tint)
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
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .islandGlass(Capsule(), tint: isSelected ? tint : nil)
    }
}
