import SwiftUI

struct ChatPanel: View {
    @ObservedObject var chat: ChatController
    /// True while the island is open, so the field can take focus each time it opens.
    let isActive: Bool
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            messagesView
            if let error = chat.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            inputBar
        }
        .onAppear {
            chat.refreshModels()
            if isActive { focusInput(after: 0) }
        }
        .onChange(of: isActive) { _, active in
            // A short dwell, so brushing past the notch doesn't steal typing from another app.
            if active { focusInput(after: 0.35) }
        }
    }

    private func focusInput(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isActive else { return }
            // The island is a non-activating panel, so ask it to take keyboard focus.
            NSApp.windows.first(where: { $0 is NotchPanel })?.makeKey()
            focused = true
        }
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty {
                        Text("Ask anything, or try “set a 10 minute timer”.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(chat.messages) { message in
                        MessageRow(message: message)
                    }
                    if chat.isThinking {
                        ProgressView().controlSize(.small)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onChange(of: chat.messages) { _, _ in
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask the assistant…", text: $chat.input)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit { chat.send() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .textCursor()

            GlassIconButton(
                systemName: chat.isBusy ? "stop.fill" : "arrow.up",
                label: chat.isBusy ? "Stop" : "Send",
                size: 28,
                tint: IslandPalette.assistant
            ) {
                if chat.isBusy { chat.stop() } else { chat.send() }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .islandGlass(Capsule())
    }
}

private struct MessageRow: View {
    let message: ChatController.Message

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .textSelection(.enabled)
                    .textCursor()
                    .islandGlass(RoundedRectangle(cornerRadius: 13, style: .continuous), tint: IslandPalette.assistant)
            }
        case .assistant:
            if !message.text.isEmpty {
                Text(markdown(message.text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textCursor()
            }
        case .status:
            HStack(spacing: 4) {
                Image(systemName: "gearshape.fill").font(.system(size: 9))
                Text(message.text).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

// MARK: - Text cursor

extension View {
    /// Shows the I-beam over this view. A non-activating panel doesn't get the system's normal
    /// cursor updates, so this tracks the pointer itself and sets the cursor directly.
    func textCursor() -> some View {
        overlay { CursorArea(cursor: .iBeam) }
    }
}

private struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorTrackingView {
        let view = CursorTrackingView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: CursorTrackingView, context: Context) {
        view.cursor = cursor
    }
}

private final class CursorTrackingView: NSView {
    var cursor: NSCursor = .iBeam

    /// Transparent to clicks and drags, so text selection and the field underneath still work.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func mouseMoved(with event: NSEvent) { cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}
