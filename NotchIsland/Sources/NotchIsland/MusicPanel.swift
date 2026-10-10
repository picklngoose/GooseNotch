import AppKit
import SwiftUI

struct MusicPanel: View {
    @ObservedObject var music: MusicController

    private var progress: Double {
        guard music.duration > 0 else { return 0 }
        return min(max(music.playbackPosition / music.duration, 0), 1)
    }

    /// The artwork's colour, or the neutral palette when there isn't one.
    private var accent: Color { music.accentColor ?? IslandPalette.music }

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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 90)

            HStack(spacing: 8) {
                Text(Self.formattedTime(music.playbackPosition))
                    .monospacedDigit()
                ScrubBar(
                    progress: progress,
                    tint: accent,
                    isEnabled: music.isAvailable && music.duration > 0,
                    onScrub: { music.scrub(toFraction: $0) },
                    onCommit: { music.commitScrub() },
                    onNudge: { music.nudge(by: $0) }
                )
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
                    tint: accent
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

/// A compact, mirrored equalizer. Apple Music doesn't expose its audio, so the motion is
/// synthesized from layered sine waves: smooth, never repeating in an obvious loop, and
/// centre-weighted like a real spectrum. Bars ease up when playback starts and settle to a row
/// of dots when it stops, instead of snapping.
/// Click or drag to seek. The track is taller than it looks so it's easy to hit, and it grows
/// under the pointer.
private struct ScrubBar: View {
    let progress: Double
    let tint: Color
    let isEnabled: Bool
    let onScrub: (Double) -> Void
    let onCommit: () -> Void
    let onNudge: (TimeInterval) -> Void

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            let thickness: CGFloat = (hovering || dragging) && isEnabled ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(geometry.size.width * progress, 0))
            }
            .frame(height: thickness)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, geometry.size.width > 0 else { return }
                        dragging = true
                        onScrub(min(max(value.location.x / geometry.size.width, 0), 1))
                    }
                    .onEnded { _ in
                        if dragging { onCommit() }
                        dragging = false
                    }
            )
        }
        .frame(height: 18)
        .onHover { hovering = $0 }
        .animation(IslandMotion.hover, value: hovering)
        .animation(IslandMotion.hover, value: dragging)
        .animation(.smooth(duration: 0.4), value: tint)
        .help(isEnabled ? "Click or drag to seek" : "")
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onNudge(10)
            case .decrement: onNudge(-10)
            @unknown default: break
            }
        }
    }
}

struct MusicVisualizer: View {
    let isPlaying: Bool
    var barCount = 20
    var color: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || reduceMotion)) { timeline in
            EqualizerBars(
                level: reduceMotion ? (isPlaying ? 0.55 : 0) : level,
                time: timeline.date.timeIntervalSinceReferenceDate,
                barCount: barCount,
                color: color
            )
        }
        .onAppear { level = isPlaying ? 1 : 0 }
        .onChange(of: isPlaying) { _, playing in
            withAnimation(playing ? .smooth(duration: 0.45) : .smooth(duration: 0.8)) {
                level = playing ? 1 : 0
            }
        }
        .accessibilityLabel(isPlaying ? "Music visualizer" : "Music paused")
    }
}

/// Animatable so `level` is interpolated every frame, even while the timeline is paused.
private struct EqualizerBars: View, Animatable {
    var level: Double
    var time: TimeInterval
    var barCount: Int
    var color: Color

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        Canvas { context, size in
            guard barCount > 0, size.width > 0, size.height > 0 else { return }
            let gap: CGFloat = size.width / CGFloat(barCount) > 5 ? 2 : 1.5
            let barWidth = max((size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount), 1)
            let restHeight = barWidth
            let midY = size.height / 2

            for index in 0..<barCount {
                let position = Double(index)
                let fraction = (position + 0.5) / Double(barCount)
                // Louder in the middle, softer at the edges.
                let envelope = 0.5 + 0.5 * sin(.pi * fraction)
                let wave =
                    0.55 * sin(time * 3.1 + position * 0.9)
                    + 0.30 * sin(time * 5.3 + position * 1.7 + 1.3)
                    + 0.15 * sin(time * 8.1 + position * 2.9 + 0.4)
                let energy = max(0, min(1, 0.5 + 0.5 * wave))
                let amplitude = energy * envelope * level

                let height = restHeight + (size.height - restHeight) * CGFloat(amplitude)
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2, style: .continuous)
                context.fill(path, with: .color(color.opacity(0.45 + 0.5 * amplitude)))
            }
        }
    }
}
