import SwiftUI

struct ChatPanel: View {
    @ObservedObject var chat: ChatController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            messagesView
            if let error = chat.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.82, green: 0.52, blue: 0.48))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            inputBar
        }
        .onAppear {
            chat.refreshModels()
            DispatchQueue.main.async {
                // The island is a non-activating panel, so ask it to take keyboard focus.
                NSApp.windows.first(where: { $0 is NotchPanel })?.makeKey()
                focused = true
            }
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
                    .islandGlass(RoundedRectangle(cornerRadius: 13, style: .continuous), tint: IslandPalette.assistant)
            }
        case .assistant:
            if !message.text.isEmpty {
                Text(markdown(message.text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
