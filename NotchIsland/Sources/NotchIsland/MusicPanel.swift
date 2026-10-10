import AppKit
import SwiftUI

struct MusicPanel: View {
    @ObservedObject var music: MusicController

    private var progress: Double {
        guard music.duration > 0 else { return 0 }
        return min(max(music.playbackPosition / music.duration, 0), 1)
    }

    private var title: String {
        music.trackTitle.isEmpty ? (music.isAvailable ? "Nothing Playing" : "Apple Music") : music.trackTitle
    }

    private var subtitle: String {
        if let error = music.errorMessage { return error }
        if !music.artist.isEmpty { return music.artist }
        return music.isAvailable ? "Choose a song in Apple Music" : "Open Apple Music to get started"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if !music.album.isEmpty {
                        Text(music.album)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    MusicVisualizer(isPlaying: music.isPlaying)
                        .frame(height: 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 90)

            HStack(spacing: 8) {
                Text(Self.formattedTime(music.playbackPosition))
                    .monospacedDigit()
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(IslandPalette.music.gradient)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 4)
                Text(Self.formattedTime(music.duration))
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 16) {
                GlassIconButton(systemName: "backward.end.fill", label: "Previous track", size: 34) {
                    music.previous()
                }
                GlassIconButton(
                    systemName: music.isPlaying ? "pause.fill" : "play.fill",
                    label: music.isPlaying ? "Pause" : "Play",
                    size: 42,
                    tint: IslandPalette.music
                ) {
                    music.togglePlayback()
                }
                GlassIconButton(systemName: "forward.end.fill", label: "Next track", size: 34) {
                    music.next()
                }
            }
            .disabled(!music.isAvailable)
            .opacity(music.isAvailable ? 1 : 0.55)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.07))
            if let data = music.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
                    .accessibilityLabel("Album artwork")
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(width: 90, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func formattedTime(_ time: TimeInterval) -> String {
        let seconds = Int(max(time, 0))
        let minutes = seconds / 60
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
}

struct MusicVisualizer: View {
    let isPlaying: Bool
    var barCount = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { timeline in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let wave = abs(sin(time * 4 + Double(index) * 0.62))
                    let overtone = abs(sin(time * 2.7 + Double(index) * 0.31))
                    Capsule()
                        .fill(.white.opacity(isPlaying ? 0.82 : 0.38))
                        .frame(width: 2, height: isPlaying ? 3 + CGFloat(wave * overtone) * 20 : 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(isPlaying ? "Music visualizer" : "Music paused")
    }
}
