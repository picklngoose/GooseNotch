import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandSession: ObservableObject {
    @Published var isExpanded = false
    @Published var geometry: NotchGeometry
    @Published private(set) var hasActivity = false

    let timer: TimerController
    let recorder: RecorderController
    let music: MusicController
    let chat: ChatController
    let appearance: IslandAppearance
    var openSettings: (() -> Void)?
    @Published var tab: IslandTab = .timer
    private var bag = Set<AnyCancellable>()

    /// The assistant and music tabs are taller; timer and recorder share the compact height.
    static func expandedHeight(for tab: IslandTab) -> CGFloat {
        tab == .chat || tab == .music ? IslandMetrics.chatHeight : IslandMetrics.expandedSize.height
    }
    var expandedHeight: CGFloat { Self.expandedHeight(for: tab) }

    init(geometry: NotchGeometry, appearance: IslandAppearance) {
        let timer = TimerController()
        let recorder = RecorderController()
        let music = MusicController()
        self.timer = timer
        self.recorder = recorder
        self.music = music
        self.chat = ChatController(timer: timer, recorder: recorder)
        self.appearance = appearance
        self.geometry = geometry

        Publishers.CombineLatest3(timer.$isRunning, recorder.$isRecording, music.$isPlaying)
            .map { $0 || $1 || $2 }
            .removeDuplicates()
            .sink { [weak self] active in self?.hasActivity = active }
            .store(in: &bag)
    }

    func quit() {
        recorder.stop()
        music.stop()
        NSApp.terminate(nil)
    }
}

@MainActor
final class IslandController {
    private let session: IslandSession
    private let panel = NotchPanel()
    private let hover = NotchHoverMonitor()
    private let settingsWindowController: AppearanceSettingsWindowController
    private var screenObserver: NSObjectProtocol?
    private var bag = Set<AnyCancellable>()

    init() {
        let geometry = NotchGeometry.current() ?? NotchGeometry(
            screenID: 0,
            screenFrame: NSScreen.main?.frame ?? .zero,
            notchFrame: NSRect(x: 0, y: 0, width: 160, height: 32),
            usingPhysicalNotch: false
        )
        let appearance = IslandAppearance()
        session = IslandSession(geometry: geometry, appearance: appearance)
        settingsWindowController = AppearanceSettingsWindowController(appearance: appearance)
    }

    func start() {
        session.openSettings = { [weak self] in self?.settingsWindowController.show() }
        let hosting = IslandHostingView(
            rootView: IslandView(
                session: session,
                appearance: session.appearance,
                timer: session.timer,
                recorder: session.recorder,
                music: session.music
            )
        )
        hosting.safeAreaRegions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        hover.onHoverChange = { [weak self] hovering in
            self?.setExpanded(hovering)
        }
        hover.onRightClick = { [weak self] in self?.settingsWindowController.show() }
        hover.start()
        session.music.start()

        // Keep the panel visible (as a compact live activity) while a timer or recording runs.
        session.$hasActivity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshVisibility()
                self.updateHover()
            }
            .store(in: &bag)

        // Keep the hover area in step with the island's height when switching tabs.
        session.$tab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in
                guard let self else { return }
                self.updateHover(expandedHeight: IslandSession.expandedHeight(for: tab))
            }
            .store(in: &bag)

        session.appearance.$expandedWidth
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHover() }
            .store(in: &bag)

        session.appearance.$activityWingWidth
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHover() }
            .store(in: &bag)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.relayout()
            }
        }

        relayout()
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
    }

    func shutdown() {
        session.recorder.stop()
        session.music.stop()
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != session.isExpanded else {
            updateHover()
            return
        }

        // The view picks the animation (springy open, quick close).
        session.isExpanded = expanded

        refreshVisibility()
        updateHover()
    }

    private func updateHover(expandedHeight: CGFloat? = nil) {
        hover.update(
            geometry: session.geometry,
            isExpanded: session.isExpanded,
            isActive: session.hasActivity,
            expandedHeight: expandedHeight ?? session.expandedHeight,
            expandedWidth: CGFloat(session.appearance.expandedWidth),
            activityWingWidth: CGFloat(session.appearance.activityWingWidth)
        )
    }

    private func refreshVisibility() {
        panel.ignoresMouseEvents = !session.isExpanded

        if session.isExpanded || session.hasActivity {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !self.session.isExpanded, !self.session.hasActivity else { return }
                self.panel.alphaValue = 0
                self.panel.ignoresMouseEvents = true
            }
        }
    }

    private func relayout() {
        guard let next = NotchGeometry.current() else { return }
        session.geometry = next
        panel.setFrame(next.windowFrame, display: true)
        updateHover()
    }
}
