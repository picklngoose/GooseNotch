import AppKit
import SwiftUI

enum IslandPalette {
    static let timer = Color(white: 0.78)
    static let assistant = Color(white: 0.94)
    static let music = Color(white: 0.86)
    static let recorder = Color(white: 0.64)
}

extension View {
    func islandGlass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        tintStrength: Double = 0.7,
        clear: Bool = false,
        blur: GlassBlur = .balanced
    ) -> some View {
        background {
            ZStack {
                InactiveGlassBackground(blur: clear ? .subtle : blur)
                    .clipShape(shape)
                if clear { shape.fill(Color.white.opacity(0.05)) }
                if let tint { shape.fill(tint.opacity(0.2 * tintStrength)) }
            }
        }
        .overlay {
            if #available(macOS 26.0, *) {
                shape.fill(Color.white.opacity(0.001))
                    .glassEffect(.clear, in: shape)
            }
        }
        .overlay { shape.stroke(.white.opacity(0.08), lineWidth: 0.5) }
    }
}

private struct InactiveGlassBackground: NSViewRepresentable {
    let blur: GlassBlur

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .inactive
        view.isEmphasized = false
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .inactive
        view.isEmphasized = false
        view.material = material
    }

    private var material: NSVisualEffectView.Material {
        switch blur {
        case .subtle, .balanced: .underWindowBackground
        case .strong: .hudWindow
        case .maximum: .fullScreenUI
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
