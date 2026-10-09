import AppKit
import AVFoundation
import Speech
import SwiftUI

@MainActor
final class RecorderController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var transcript = ""
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 20)
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isTranscribing = false

    private let capture = AudioCapture()
    private var startDate: Date?
    private var currentURL: URL?
    private var ticker: Timer?
    private var isStarting = false

    static var memosFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch Memos", isDirectory: true)
    }

    var formattedElapsed: String { TimerController.format(elapsed) }

    func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await begin() }
        }
    }

    private func begin() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        errorMessage = nil

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is off. Enable it in System Settings › Privacy."
            return
        }
        let speechAllowed = await Self.requestSpeech()

        do {
            try FileManager.default.createDirectory(at: Self.memosFolder, withIntermediateDirectories: true)
            let url = Self.newRecordingURL()

            capture.onLevel = { @Sendable [weak self] level in
                Task { @MainActor in self?.push(level: level) }
            }
            capture.onTranscript = { @Sendable [weak self] text in
                Task { @MainActor in self?.transcript = text }
            }

            try capture.start(url: url, transcribe: speechAllowed)

            isTranscribing = capture.isTranscribing
            if !speechAllowed {
                errorMessage = "Speech recognition is off, so there's no live transcript."
            }
            transcript = ""
            elapsed = 0
            lastRecordingURL = nil
            currentURL = url
            startDate = Date()
            isRecording = true
            startTicker()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else { return }
        capture.stop()
        isRecording = false
        stopTicker()
        if let startDate { elapsed = Date().timeIntervalSince(startDate) }
        levels = Array(repeating: 0, count: levels.count)

        let url = currentURL
        lastRecordingURL = url

        // Give the recognizer a moment to deliver its final words, then save the transcript.
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !self.isRecording, let url, !self.transcript.isEmpty else { return }
            let txt = url.deletingPathExtension().appendingPathExtension("txt")
            try? self.transcript.write(to: txt, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Actions on the last recording

    func revealLastRecording() {
        if let url = lastRecordingURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(Self.memosFolder)
        }
    }

    /// Hands the file to Voice Memos so it's imported into your library.
    func openInVoiceMemos() {
        guard let url = lastRecordingURL else { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.VoiceMemos") {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            revealLastRecording()
        }
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    // MARK: Helpers

    private func push(level: Float) {
        guard isRecording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private static func newRecordingURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return memosFolder.appendingPathComponent("Memo \(f.string(from: Date())).m4a")
    }

    nonisolated private static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
