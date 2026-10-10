import AppKit
import SwiftUI

private enum MusicScriptResult {
    case success(NSAppleEventDescriptor)
    case failure(String)
}

private enum MusicCommand: String {
    case previous = "previous track"
    case playPause = "playpause"
    case next = "next track"
}

private struct MusicSnapshot: Sendable {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let position: TimeInterval
    let duration: TimeInterval
    let artwork: Data?
}

private enum MusicFetchResult: Sendable {
    case snapshot(MusicSnapshot)
    case notRunning
    case failure(String)
}

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var trackTitle = ""
    @Published private(set) var trackID = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artworkData: Data?
    @Published private(set) var isPlaying = false
    @Published private(set) var isAvailable = false
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private let worker = DispatchQueue(label: "com.goosenotch.music", qos: .utility)
    private var poller: Timer?
    private var refreshInFlight = false
    private var commandInFlight = false

    func start() {
        guard poller == nil else { return }
        refresh()
        poller = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        poller?.invalidate()
        poller = nil
    }

    func previous() { send(.previous) }
    func togglePlayback() { send(.playPause) }
    func next() { send(.next) }

    private func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let knownTrackID = trackID
        worker.async {
            let result = Self.fetchSnapshot(knownTrackID: knownTrackID)
            Task { @MainActor [weak self] in
                self?.apply(result)
            }
        }
    }

    private func send(_ command: MusicCommand) {
        guard isAvailable, !commandInFlight else { return }
        commandInFlight = true
        let commandName = command.rawValue
        worker.async {
            let failureMessage: String?
            switch Self.execute(
                """
                tell application "Music" to \(commandName)
                """
            ) {
            case .success:
                failureMessage = nil
            case let .failure(message):
                failureMessage = message
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.commandInFlight = false
                self.errorMessage = failureMessage
                self.refresh()
            }
        }
    }

    private func apply(_ result: MusicFetchResult) {
        refreshInFlight = false
        switch result {
        case let .snapshot(snapshot):
            isAvailable = true
            if trackID != snapshot.trackID {
                trackID = snapshot.trackID
                artworkData = snapshot.artwork
            }
            trackTitle = snapshot.title
            artist = snapshot.artist
            album = snapshot.album
            isPlaying = snapshot.isPlaying
            playbackPosition = snapshot.position
            duration = snapshot.duration
            errorMessage = nil
        case .notRunning:
            isAvailable = false
            clearTrack()
            errorMessage = nil
        case let .failure(message):
            isAvailable = true
            clearTrack()
            errorMessage = message
        }
    }

    private func clearTrack() {
        trackTitle = ""
        trackID = ""
        artist = ""
        album = ""
        artworkData = nil
        isPlaying = false
        playbackPosition = 0
        duration = 0
    }

    private nonisolated static func fetchSnapshot(knownTrackID: String) -> MusicFetchResult {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return .notRunning
        }

        let escapedTrackID = knownTrackID.replacingOccurrences(of: "\"", with: "\"\"")
        let result = execute(
            """
            tell application "Music"
                try
                    set currentTrack to current track
                on error
                    return {"", "", "", "stopped", 0, 0, "", ""}
                end try
                set trackTitle to name of currentTrack as text
                set trackArtist to artist of currentTrack as text
                set trackAlbum to album of currentTrack as text
                set trackState to player state as text
                set trackPosition to player position as real
                set trackDuration to duration of currentTrack as real
                set trackIdentifier to persistent ID of currentTrack as text
                set artworkData to ""
                if trackIdentifier is not "\(escapedTrackID)" then
                    try
                        set artworkData to data of artwork 1 of currentTrack
                    end try
                end if
                return {trackTitle, trackArtist, trackAlbum, trackState, trackPosition, trackDuration, trackIdentifier, artworkData}
            end tell
            """
        )

        switch result {
        case let .success(descriptor):
            guard descriptor.numberOfItems >= 8 else {
                return .failure("Apple Music returned incomplete track information.")
            }
            let title = descriptor.atIndex(1)?.stringValue ?? ""
            let state = descriptor.atIndex(4)?.stringValue ?? "stopped"
            return .snapshot(
                MusicSnapshot(
                    trackID: descriptor.atIndex(7)?.stringValue ?? "",
                    title: title,
                    artist: descriptor.atIndex(2)?.stringValue ?? "",
                    album: descriptor.atIndex(3)?.stringValue ?? "",
                    isPlaying: state == "playing",
                    position: descriptor.atIndex(5)?.doubleValue ?? 0,
                    duration: descriptor.atIndex(6)?.doubleValue ?? 0,
                    artwork: descriptor.atIndex(8)?.data
                )
            )
        case let .failure(message):
            return .failure(message)
        }
    }

    private nonisolated static func execute(_ source: String) -> MusicScriptResult {
        guard let script = NSAppleScript(source: source) else {
            return .failure("Could not prepare an Apple Music command.")
        }
        var error: NSDictionary?
        guard let descriptor = script.executeAndReturnError(&error) else {
            let number = error?["NSAppleScriptErrorNumber"] as? Int
            if number == -1743 {
                return .failure("Allow Goosenotch to control Apple Music in System Settings > Privacy & Security > Automation.")
            }
            let message = error?["NSAppleScriptErrorMessage"] as? String
            return .failure(message ?? "Apple Music did not respond to the request.")
        }
        return .success(descriptor)
    }
}
