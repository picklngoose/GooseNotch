import AppKit
import SwiftUI

// MARK: - Tools the assistant can use

/// Small, deliberately safe set of Mac actions. No shell access or file writes.
enum ChatTools {
    static var definitions: [[String: Any]] {
        [
            tool("set_timer",
                 "Set the countdown timer and optionally start it.",
                 ["minutes": prop("number", "Duration in minutes (decimals allowed)."),
                  "start": prop("boolean", "Start immediately. Defaults to true.")],
                 required: ["minutes"]),
            tool("timer_control",
                 "Start, pause or reset the timer.",
                 ["action": prop("string", "One of: start, pause, reset.", options: ["start", "pause", "reset"])],
                 required: ["action"]),
            tool("recording_control",
                 "Start or stop the voice recorder (with live transcript).",
                 ["action": prop("string", "One of: start, stop.", options: ["start", "stop"])],
                 required: ["action"]),
            tool("get_current_time",
                 "Get the current local date and time.",
                 [:],
                 required: []),
            tool("copy_to_clipboard",
                 "Copy text to the user's clipboard.",
                 ["text": prop("string", "The text to copy.")],
                 required: ["text"]),
            tool("open_url",
                 "Open an http or https URL in the default browser.",
                 ["url": prop("string", "The full URL, including https://.")],
                 required: ["url"]),
            tool("open_application",
                 "Launch a Mac application by name, e.g. Safari or Notes.",
                 ["name": prop("string", "The application name.")],
                 required: ["name"])
        ]
    }

    private static func prop(_ type: String, _ description: String, options: [String]? = nil) -> [String: Any] {
        var p: [String: Any] = ["type": type, "description": description]
        if let options { p["enum"] = options }
        return p
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String]) -> [String: Any] {
        let parameters: [String: Any] = ["type": "object", "properties": properties, "required": required]
        let function: [String: Any] = ["name": name, "description": description, "parameters": parameters]
        return ["type": "function", "function": function]
    }
}

// MARK: - Chat controller

@MainActor
final class ChatController: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant, status }
        let id = UUID()
        var role: Role
        var text: String
    }

    @Published private(set) var messages: [Message] = []
    @Published var input = ""
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var models: [String] = []
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "ollamaModel") }
    }

    private let client = OllamaClient()
    private let timer: TimerController
    private let recorder: RecorderController
    private var history: [ChatTurn] = []
    private var task: Task<Void, Never>?

    init(timer: TimerController, recorder: RecorderController) {
        self.timer = timer
        self.recorder = recorder
        self.selectedModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? ""
    }

    var isThinking: Bool {
        guard isBusy else { return false }
        guard let last = messages.last else { return true }
        return last.role != .assistant || last.text.isEmpty
    }

    // MARK: Models

    func refreshModels() {
        Task {
            do {
                let list = try await client.listModels()
                models = list
                if selectedModel.isEmpty || !list.contains(selectedModel) {
                    selectedModel = list.first ?? ""
                }
                if !isBusy { errorMessage = nil }
            } catch {
                if !isBusy { errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: Sending

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard !selectedModel.isEmpty else {
            errorMessage = "No model selected. Run `ollama pull <model>`, or `ollama signin` for cloud models."
            refreshModels()
            return
        }

        input = ""
        errorMessage = nil
        messages.append(Message(role: .user, text: text))
        history.append(ChatTurn(role: "user", content: text))
        isBusy = true

        task = Task { [weak self] in
            await self?.runAgentLoop()
            self?.isBusy = false
        }
    }

    func stop() {
        task?.cancel()
        isBusy = false
        messages.removeAll { $0.role == .assistant && $0.text.isEmpty }
    }

    func clear() {
        stop()
        messages = []
        history = []
        errorMessage = nil
    }

    // MARK: Agent loop

    private func systemTurn() -> ChatTurn {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return ChatTurn(role: "system", content: """
            You are a fast, concise assistant that lives in the notch of the user's Mac. \
            Keep replies to one to three sentences unless asked for more. \
            You can control the Mac's timer and voice recorder, open apps and URLs, and copy text to the clipboard \
            using tools. When the user asks you to do one of those things, call the tool instead of describing it. \
            It is currently \(f.string(from: Date())).
            """)
    }

    private func runAgentLoop() async {
        var useTools = true
        var round = 0

        while round < 6 {
            round += 1
            let placeholder = Message(role: .assistant, text: "")
            messages.append(placeholder)
            let id = placeholder.id
            var content = ""
            var calls: [ToolCall] = []

            do {
                let stream = client.chatStream(
                    model: selectedModel,
                    turns: [systemTurn()] + history,
                    tools: useTools ? ChatTools.definitions : []
                )
                for try await event in stream {
                    switch event {
                    case .content(let chunk):
                        content += chunk
                        setText(content, for: id)
                    case .toolCalls(let newCalls):
                        calls += newCalls
                    }
                }
            } catch {
                removeIfEmpty(id)
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                if useTools, error.localizedDescription.localizedCaseInsensitiveContains("support tools") {
                    // This model can't call tools; fall back to plain chat.
                    useTools = false
                    round -= 1
                    continue
                }
                errorMessage = error.localizedDescription
                return
            }

            if Task.isCancelled { removeIfEmpty(id); return }

            history.append(ChatTurn(role: "assistant", content: content, toolCalls: calls))

            if calls.isEmpty {
                if content.isEmpty { setText("(no response)", for: id) }
                return
            }

            removeIfEmpty(id)
            for call in calls {
                messages.append(Message(role: .status, text: label(for: call)))
                let result = run(call)
                history.append(ChatTurn(role: "tool", content: result, toolName: call.name))
            }
        }
        errorMessage = "Stopped after too many tool steps."
    }

    private func setText(_ text: String, for id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].text = text }
    }

    private func removeIfEmpty(_ id: UUID) {
        messages.removeAll { $0.id == id && $0.text.isEmpty }
    }

    private func label(for call: ToolCall) -> String {
        let args = call.arguments.sorted { $0.key < $1.key }.map(\.value).joined(separator: ", ")
        let text = args.isEmpty ? call.name : "\(call.name) · \(args)"
        return text.count > 48 ? String(text.prefix(47)) + "…" : text
    }

    // MARK: Tool execution

    private func run(_ call: ToolCall) -> String {
        let args = call.arguments
        switch call.name {
        case "set_timer":
            guard let minutes = Double(args["minutes"] ?? ""), minutes > 0 else { return "Error: 'minutes' must be a positive number." }
            timer.reset()
            timer.mode = .countdown
            timer.setDuration(seconds: Int((minutes * 60).rounded()))
            if args["start"] != "false" {
                timer.toggle()
                return "Timer set for \(TimerController.format(timer.duration)) and started."
            }
            return "Timer set for \(TimerController.format(timer.duration)), not started."

        case "timer_control":
            switch args["action"] {
            case "start": if !timer.isRunning { timer.toggle() }; return "Timer running."
            case "pause": if timer.isRunning { timer.toggle() }; return "Timer paused."
            case "reset": timer.reset(); return "Timer reset."
            default: return "Error: action must be start, pause or reset."
            }

        case "recording_control":
            switch args["action"] {
            case "start":
                if recorder.isRecording { return "Already recording." }
                recorder.toggle()
                return "Recording started. macOS may ask for microphone permission the first time."
            case "stop":
                if !recorder.isRecording { return "Not recording." }
                recorder.stop()
                return "Recording stopped and saved."
            default: return "Error: action must be start or stop."
            }

        case "get_current_time":
            let f = DateFormatter()
            f.dateStyle = .full
            f.timeStyle = .medium
            return f.string(from: Date())

        case "copy_to_clipboard":
            guard let text = args["text"], !text.isEmpty else { return "Error: 'text' is required." }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "Copied to clipboard."

        case "open_url":
            guard let raw = args["url"], let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else { return "Error: only http and https URLs can be opened." }
            NSWorkspace.shared.open(url)
            return "Opened \(raw)."

        case "open_application":
            let name = (args["name"] ?? "").replacingOccurrences(of: ".app", with: "")
            guard !name.isEmpty, !name.contains("/") else { return "Error: invalid application name." }
            let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
            for folder in folders {
                let path = "\(folder)/\(name).app"
                if FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    return "Opened \(name)."
                }
            }
            return "Couldn't find an app named \(name)."

        default:
            return "Error: unknown tool '\(call.name)'."
        }
    }
}
