import SwiftUI

enum IslandTab: Hashable {
    case timer, chat, record
}

struct IslandView: View {
    @ObservedObject var session: IslandSession
    @ObservedObject var appearance: IslandAppearance
    @ObservedObject var timer: TimerController
    @ObservedObject var recorder: RecorderController
    @State private var showingModelPrompt = false
    @State private var customModelName = ""

    private var tab: IslandTab { session.tab }
    private var expanded: Bool { session.isExpanded }
    private var wingWidth: CGFloat { CGFloat(appearance.activityWingWidth) }
    private var expandedWidth: CGFloat { CGFloat(appearance.expandedWidth) }
    private var cornerRadius: CGFloat { CGFloat(appearance.cornerRadius) }

    var body: some View {
        let notch = session.geometry.notchSize

        ZStack(alignment: .top) {
            islandBody(notch: notch)

            if !expanded && session.hasActivity {
                wings(notch: notch)
                    .transition(.opacity)
            }

            // Content stays in the tree and is clipped by the (animating) island shape, so on
            // collapse it looks like the notch closes around it instead of the content vanishing.
            content(notch: notch)
                .scaleEffect(expanded ? 1 : 0.96, anchor: .top)
                .opacity(expanded ? 1 : 0)
                .animation(
                    expanded
                        ? Animation.easeOut(duration: 0.24).delay(0.08)
                        : Animation.easeIn(duration: 0.16).delay(0.04),
                    value: expanded
                )
                .mask(alignment: .top) {
                    ConnectedIslandShape(
                        progress: expanded ? 1 : 0,
                        activityProgress: expanded || !session.hasActivity ? 0 : 1,
                        notchWidth: notch.width,
                        notchHeight: notch.height,
                        activityWidth: notch.width + wingWidth * 2,
                        cornerRadius: cornerRadius
                    )
                    .frame(width: expandedWidth, height: session.expandedHeight)
                }
                .allowsHitTesting(expanded)
        }
        .frame(
            width: IslandMetrics.windowSize.width,
            height: IslandMetrics.windowSize.height,
            alignment: .top
        )
        .environment(\.colorScheme, .dark)
        .tint(Color(white: 0.78))
        .animation(
            expanded
                ? Animation.spring(response: 0.38, dampingFraction: 0.84)
                : Animation.smooth(duration: 0.3),
            value: expanded
        )
        .animation(.easeInOut(duration: 0.25), value: session.hasActivity)
        .onChange(of: recorder.isRecording) { _, recording in
            if recording { withAnimation(.smooth(duration: 0.28)) { session.tab = .record } }
        }
        .onChange(of: expanded) { _, isOpen in
            // Drop keyboard focus (e.g. mid-edit on the timer) when the island closes.
            if !isOpen {
                NSApp.windows.first(where: { $0 is NotchPanel })?.makeFirstResponder(nil)
            }
        }
        .contextMenu {
            Button("Notch Appearance…") { session.openSettings?() }
            Button("Open Notch Memos Folder") { recorder.revealLastRecording() }
            Divider()
            Button("Quit Goosenotch") { session.quit() }
        }
    }

    // MARK: Body — black like the notch at the top, easing into Liquid Glass at the bottom

    @ViewBuilder
    private func islandBody(notch: NSSize) -> some View {
        let shape = ConnectedIslandShape(
            progress: expanded ? 1 : 0,
            activityProgress: expanded || !session.hasActivity ? 0 : 1,
            notchWidth: notch.width,
            notchHeight: notch.height,
            activityWidth: notch.width + wingWidth * 2,
            cornerRadius: cornerRadius
        )
        ZStack {
            shape.fill(Color.black.opacity(0.01))
                .islandGlass(
                    shape,
                    tint: appearance.tintStrength > 0 ? appearance.tintColor : nil,
                    tintStrength: appearance.tintStrength,
                    clear: appearance.blur == .subtle,
                    blur: appearance.blur
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.3),
                            .init(color: .black.opacity(0.35), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.34),
                        .init(color: .black.opacity(0.22), location: 0.72),
                        .init(color: .black.opacity(0.0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            if appearance.tintStrength > 0 {
                shape.fill(appearance.tintColor.opacity(appearance.tintStrength))
            }
            // Thin bright rim that strengthens toward the bottom, like real glass edges.
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0.3),
                        .init(color: .white.opacity(0.28 * appearance.rimStrength), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
        .opacity(appearance.opacity)
        .frame(width: expandedWidth, height: session.expandedHeight)
    }

    // MARK: Expanded content

    private func content(notch: NSSize) -> some View {
        VStack(spacing: 10) {
            topRow(notch: notch)
            Group {
                switch tab {
                case .timer: TimerPanel(timer: timer)
                case .chat: ChatPanel(chat: session.chat)
                case .record: RecorderPanel(recorder: recorder)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 0)
        .padding(.horizontal, 38)
        .padding(.bottom, 16)
        .frame(
            width: expandedWidth,
            height: session.expandedHeight,
            alignment: .top
        )
    }

    /// Tabs sit level with the notch, split around it so nothing ends up underneath it.
    private func topRow(notch: NSSize) -> some View {
        let zone = max((expandedWidth - 76 - notch.width) / 2 - 8, 60)
        return HStack(spacing: 0) {
            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    tabChip(.timer, icon: "timer", label: "Timer", tint: IslandPalette.timer)
                    tabChip(.chat, icon: "sparkles", label: "Assistant", tint: IslandPalette.assistant)
                }
            }
            .frame(width: zone, alignment: .leading)

            Color.clear.frame(width: notch.width + 16)

            HStack(spacing: 6) {
                if tab == .chat { modelMenu }
                tabChip(.record, icon: "waveform", label: "Record", tint: IslandPalette.recorder)
            }
            .frame(width: zone, alignment: .trailing)
        }
        .frame(height: notch.height)
    }

    private func tabChip(_ target: IslandTab, icon: String, label: String, tint: Color) -> some View {
        GlassChip(title: "", systemImage: icon, isSelected: tab == target, tint: tint) {
            withAnimation(.smooth(duration: 0.28)) { session.tab = target }
        }
        .accessibilityLabel(label)
        .help(label)
    }

    private var modelMenu: some View {
        Menu {
            if session.chat.selectableModels.isEmpty { Text("No models found") }
            ForEach(session.chat.selectableModels, id: \.self) { name in
                Button {
                    session.chat.selectModel(name)
                } label: {
                    if name == session.chat.selectedModel {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            Divider()
            Button("Add Model…") {
                customModelName = ""
                showingModelPrompt = true
            }
            Button("Refresh Models") { session.chat.refreshModels() }
            Button("New Chat") { session.chat.clear() }
        } label: {
            HStack(spacing: 5) {
                if session.chat.isPreparingModel { ProgressView().controlSize(.mini) }
                Text(session.chat.selectedModel.isEmpty ? "Model" : session.chat.selectedModel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
            }
                .frame(maxWidth: 52)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .islandGlass(Capsule(), interactive: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .alert("Add Ollama Model", isPresented: $showingModelPrompt) {
            TextField("Model name", text: $customModelName)
            Button("Cancel", role: .cancel) { customModelName = "" }
            Button("Use Model") { session.chat.selectModel(customModelName) }
        } message: {
            Text("Enter a model name available to your local or signed-in Ollama account.")
        }
    }

    // MARK: Collapsed "live activity" wings

    private func wings(notch: NSSize) -> some View {
        HStack(spacing: 0) {
            leftWing.frame(width: wingWidth)
            Color.clear.frame(width: notch.width)
            rightWing.frame(width: wingWidth)
        }
        .frame(height: notch.height)
    }

    @ViewBuilder
    private var leftWing: some View {
        if recorder.isRecording {
            HStack(spacing: 5) {
                PulsingDot()
                MiniMeter(levels: Array(recorder.levels.suffix(5)))
                    .frame(width: 22, height: 14)
            }
        } else {
            Image(systemName: timer.mode == .countdown ? "timer" : "stopwatch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandPalette.timer)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if timer.isRunning {
            Text(timer.formatted)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(IslandPalette.timer)
        } else if recorder.isRecording {
            Text(recorder.formattedElapsed)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Timer tab

struct TimerPanel: View {
    @ObservedObject var timer: TimerController
    @State private var isEditing = false
    @State private var entry = ""
    @FocusState private var focused: Bool

    private let presets = [1, 5, 10, 25]
    private let accent = IslandPalette.timer

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                timeDisplay
                Spacer()
                GlassGroup(spacing: 12) {
                    HStack(spacing: 10) {
                        GlassIconButton(systemName: "arrow.counterclockwise", label: "Reset", size: 38) {
                            timer.reset()
                        }
                        GlassIconButton(
                            systemName: timer.isRunning ? "pause.fill" : "play.fill",
                            label: timer.isRunning ? "Pause" : "Start",
                            size: 46,
                            tint: accent
                        ) { toggleTimer() }
                    }
                }
            }

            progressBar

            HStack(spacing: 8) {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 6) {
                        if timer.mode == .countdown {
                            ForEach(presets, id: \.self) { minutes in
                                GlassChip(
                                    title: "\(minutes)m",
                                    isSelected: timer.duration == TimeInterval(minutes * 60),
                                    tint: accent,
                                    isDisabled: timer.isRunning
                                ) { timer.setMinutes(minutes) }
                            }
                        }
                    }
                }
                Spacer()
                GlassGroup(spacing: 8) {
                    HStack(spacing: 6) {
                        GlassChip(title: "", systemImage: "hourglass", isSelected: timer.mode == .countdown, tint: accent) {
                            timer.mode = .countdown
                        }
                        .accessibilityLabel("Countdown")
                        GlassChip(title: "", systemImage: "stopwatch", isSelected: timer.mode == .stopwatch, tint: accent) {
                            timer.mode = .stopwatch
                        }
                        .accessibilityLabel("Stopwatch")
                    }
                }
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && isEditing { commitEdit() }
        }
    }

    // MARK: Time display / keyboard entry

    @ViewBuilder
    private var timeDisplay: some View {
        if isEditing {
            editingDisplay
        } else {
            Text(timer.formatted)
                .font(.system(size: 52, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: timer.mode == .countdown))
                .animation(.snappy, value: timer.formatted)
                .onTapGesture { beginEdit() }
                .help(timer.mode == .countdown && !timer.isRunning ? "Click to type a custom time" : "")
        }
    }

    /// Digits fill in from the right, like Apple's Clock app: typing 1, 3, 0 gives 00:01:30.
    private var editingDisplay: some View {
        let typed = entry.count
        let padded = Array(String(repeating: "0", count: 6 - typed) + entry)

        return HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                if i > 0 && i % 2 == 0 {
                    Text(":").foregroundStyle(Color.white.opacity(0.35))
                }
                Text(String(padded[i]))
                    .foregroundStyle(i >= 6 - typed ? Color.white : Color.white.opacity(0.35))
            }
        }
        .font(.system(size: 52, weight: .light, design: .rounded))
        .monospacedDigit()
        .overlay(alignment: .bottom) {
            Capsule().fill(accent).frame(height: 2).offset(y: 4)
        }
        .background {
            // Invisible field that receives the keystrokes.
            TextField("", text: $entry)
                .textFieldStyle(.plain)
                .focused($focused)
                .opacity(0.01)
                .frame(width: 2, height: 2)
                .onSubmit { commitEdit() }
                .onExitCommand { cancelEdit() }
                .onChange(of: entry) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if digits != new { entry = digits }
                }
        }
    }

    private func beginEdit() {
        guard timer.mode == .countdown, !timer.isRunning else { return }
        entry = ""
        isEditing = true
        // The island is a non-activating panel, so ask it to take keyboard focus.
        NSApp.windows.first(where: { $0 is NotchPanel })?.makeKey()
        DispatchQueue.main.async { focused = true }
    }

    private func toggleTimer() {
        if isEditing { commitEdit() }
        timer.toggle()
    }

    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        focused = false
        if !entry.isEmpty {
            let padded = String(repeating: "0", count: 6 - entry.count) + entry
            let n = padded.compactMap { $0.wholeNumberValue }
            if n.count == 6 {
                let total = (n[0] * 10 + n[1]) * 3600 + (n[2] * 10 + n[3]) * 60 + (n[4] * 10 + n[5])
                if total > 0 { timer.setDuration(seconds: total) }
            }
        }
        entry = ""
    }

    private func cancelEdit() {
        isEditing = false
        focused = false
        entry = ""
    }

    // MARK: Progress

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(accent.gradient)
                    .frame(width: geo.size.width * timer.progress)
            }
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.25), value: timer.progress)
    }
}

// MARK: - Record tab

struct RecorderPanel: View {
    @ObservedObject var recorder: RecorderController

    private var status: String {
        if let error = recorder.errorMessage { return error }
        if recorder.isRecording { return recorder.isTranscribing ? "Recording · live transcript" : "Recording" }
        if recorder.lastRecordingURL != nil { return "Saved to Notch Memos" }
        return "Ready"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                GlassIconButton(
                    systemName: recorder.isRecording ? "stop.fill" : "mic.fill",
                    label: recorder.isRecording ? "Stop recording" : "Start recording",
                    size: 42,
                    tint: IslandPalette.recorder
                ) { recorder.toggle() }

                VStack(alignment: .leading, spacing: 2) {
                    Text(recorder.formattedElapsed)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                if recorder.isRecording {
                    LevelMeter(levels: recorder.levels)
                        .frame(width: 72, height: 28)
                } else if recorder.lastRecordingURL != nil {
                    GlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            GlassIconButton(systemName: "folder", label: "Show in Finder", size: 30) {
                                recorder.revealLastRecording()
                            }
                            GlassIconButton(systemName: "waveform", label: "Open in Voice Memos", size: 30) {
                                recorder.openInVoiceMemos()
                            }
                            GlassIconButton(systemName: "doc.on.doc", label: "Copy transcript", size: 30) {
                                recorder.copyTranscript()
                            }
                        }
                    }
                }
            }

            TranscriptView(text: recorder.transcript)
        }
    }
}

struct TranscriptView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.isEmpty ? "Live transcript appears here." : text)
                        .font(.system(size: 12))
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: text) { _, _ in
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .islandGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Small visual pieces

struct LevelMeter: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 2.5, height: max(3, CGFloat(level) * 28))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
    }
}

struct MiniMeter: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: max(3, CGFloat(level) * 14))
            }
        }
    }
}

struct PulsingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(IslandPalette.recorder)
            .frame(width: 8, height: 8)
            .opacity(on ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
