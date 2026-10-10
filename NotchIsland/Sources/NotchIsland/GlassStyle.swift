import SwiftUI

enum IslandPalette {
    static let timer = Color(red: 0.74, green: 0.54, blue: 0.34)
    static let assistant = Color(red: 0.36, green: 0.58, blue: 0.77)
    static let recorder = Color(red: 0.70, green: 0.41, blue: 0.37)
}

// MARK: - Liquid Glass helpers
//
// On macOS 26+ these use the real Liquid Glass APIs (glassEffect / GlassEffectContainer).
// On macOS 14–15 they fall back to system materials so the app still looks native.

@available(macOS 26.0, *)
private func makeIslandGlass(tint: Color?, interactive: Bool, clear: Bool) -> Glass {
    var glass = clear ? Glass.clear : Glass.regular
    if let tint { glass = glass.tint(tint.opacity(0.7)) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    @ViewBuilder
    func islandGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, clear: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(makeIslandGlass(tint: tint, interactive: interactive, clear: clear), in: shape)
        } else {
            self.background {
                shape.fill(clear ? AnyShapeStyle(Color.white.opacity(0.05)) : AnyShapeStyle(.ultraThinMaterial))
                if let tint { shape.fill(tint.opacity(0.2)) }
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
        .islandGlass(Circle(), tint: tint, interactive: true)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    var tint: Color = .accentColor
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
        .islandGlass(Capsule(), tint: isSelected ? tint : nil, interactive: true)
    }
}
