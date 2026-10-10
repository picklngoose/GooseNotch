import AppKit
import SwiftUI

@MainActor
final class TimerController: ObservableObject {
    enum Mode { case countdown, stopwatch }

    @Published var mode: Mode = .countdown {
        didSet { if mode != oldValue { reset() } }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 5 * 60

    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var ticker: Timer?

    var displayTime: TimeInterval {
        mode == .countdown ? ceil(max(duration - elapsed, 0)) : elapsed
    }

    var formatted: String { Self.format(displayTime) }

    nonisolated static func format(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// 0–1 fill for the progress bar: time remaining (countdown) or the current minute (stopwatch).
    var progress: Double {
        switch mode {
        case .countdown:
            return duration > 0 ? max(0, min(1, 1 - elapsed / duration)) : 0
        case .stopwatch:
            return elapsed.truncatingRemainder(dividingBy: 60) / 60
        }
    }

    func setDuration(seconds: Int) {
        guard !isRunning else { return }
        duration = TimeInterval(min(max(seconds, 1), 99 * 3600 + 59 * 60 + 59))
        reset()
    }

    func setMinutes(_ minutes: Int) {
        guard !isRunning else { return }
        duration = TimeInterval(minutes * 60)
        reset()
    }

    func toggle() {
        if isRunning {
            accumulated = elapsed
            stopTicker()
            isRunning = false
            return
        }
        if mode == .countdown, elapsed >= duration { reset() }
        if mode == .countdown { TimerAlert.shared.prepare() }
        startDate = Date()
        isRunning = true
        startTicker()
    }

    func reset() {
        stopTicker()
        isRunning = false
        accumulated = 0
        elapsed = 0
        startDate = nil
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let startDate else { return }
        elapsed = accumulated + Date().timeIntervalSince(startDate)
        if mode == .countdown, elapsed >= duration {
            elapsed = duration
            accumulated = duration
            stopTicker()
            isRunning = false
            TimerAlert.shared.timerFinished(duration: duration)
        }
    }
}
