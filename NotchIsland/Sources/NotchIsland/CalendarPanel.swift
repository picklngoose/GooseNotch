import AppKit
import SwiftUI

/// The Calendar tab: a detail card with a live countdown on the left, the agenda on the right.
struct CalendarPanel: View {
    @ObservedObject var calendar: CalendarController
    /// Pauses the once-a-second countdown while the island is closed.
    let isActive: Bool

    var body: some View {
        Group {
            switch calendar.access {
            case .authorized:
                if calendar.events.isEmpty {
                    CalendarMessage(
                        icon: "calendar",
                        title: "All clear",
                        detail: calendar.errorMessage ?? "Nothing scheduled for the next 7 days.",
                        actionTitle: calendar.errorMessage == nil ? nil : "Try Again",
                        action: { calendar.refresh() }
                    )
                } else {
                    HStack(alignment: .top, spacing: IslandSpacing.l) {
                        EventDetailCard(calendar: calendar, isActive: isActive)
                            .frame(width: 208)
                        AgendaList(calendar: calendar)
                    }
                }
            case .notDetermined:
                CalendarMessage(
                    icon: "calendar.badge.clock",
                    title: "See what's next",
                    detail: calendar.errorMessage ?? "Show upcoming events and a countdown right in the notch.",
                    actionTitle: calendar.isRequesting ? "Waiting…" : "Connect Calendar",
                    isActionDisabled: calendar.isRequesting,
                    action: { calendar.requestAccess() }
                )
            case .denied:
                CalendarMessage(
                    icon: "calendar.badge.exclamationmark",
                    title: "Calendar access is off",
                    detail: "Allow Goosenotch under Privacy & Security › Calendars.",
                    actionTitle: "Open Settings",
                    action: { calendar.openPrivacySettings() }
                )
            case .writeOnly:
                CalendarMessage(
                    icon: "calendar.badge.exclamationmark",
                    title: "Full access needed",
                    detail: "Goosenotch can only add events. Choose Full Access in Privacy & Security › Calendars.",
                    actionTitle: "Open Settings",
                    action: { calendar.openPrivacySettings() }
                )
            case .restricted:
                CalendarMessage(
                    icon: "lock.fill",
                    title: "Calendar is restricted",
                    detail: "Calendar access is limited by a device policy on this Mac."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(IslandMotion.tab, value: calendar.access)
    }
}

// MARK: - Detail card

private struct EventDetailCard: View {
    @ObservedObject var calendar: CalendarController
    let isActive: Bool

    var body: some View {
        Group {
            if let event = calendar.focusedEvent {
                card(for: event)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .islandGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func card(for event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: event.calendarColor))
                    .frame(width: 7, height: 7)
                Text(event.calendarTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            TimelineView(.animation(minimumInterval: 1, paused: !isActive)) { timeline in
                let countdown = CalendarFormat.countdown(for: event, now: timeline.date)
                VStack(alignment: .leading, spacing: 0) {
                    Text(countdown.label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(countdown.value)
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: countdown.value)
                }
            }
            .padding(.top, 4)

            Text(event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .help(event.title)

            Text(CalendarFormat.timeRange(for: event))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)

            if let location = event.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(location)
            }

            Spacer(minLength: IslandSpacing.xs)

            HStack(spacing: IslandSpacing.s) {
                if let join = event.joinURL {
                    GlassChip(title: "Join", systemImage: "video.fill", isSelected: true, tint: IslandPalette.calendar) {
                        calendar.open(join)
                    }
                }
                Spacer(minLength: 0)
                GlassIconButton(systemName: "arrow.up.forward.app", label: "Open in Calendar", size: 28) {
                    calendar.openCalendarApp()
                }
            }
        }
        .padding(IslandSpacing.m)
        .transition(.opacity)
        .id(event.id)
    }
}

// MARK: - Agenda

private struct AgendaList: View {
    @ObservedObject var calendar: CalendarController

    private struct DayGroup: Identifiable {
        let day: Date
        let events: [CalendarEvent]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let cal = Calendar.current
        let now = Date()
        let grouped = Dictionary(grouping: calendar.events) { cal.startOfDay(for: max($0.start, now)) }
        return grouped.keys.sorted().map { DayGroup(day: $0, events: grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IslandSpacing.xs) {
                ForEach(groups) { group in
                    Text(CalendarFormat.dayTitle(for: group.day).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, IslandSpacing.s)
                        .padding(.top, group.id == groups.first?.id ? 0 : IslandSpacing.s)

                    ForEach(group.events) { event in
                        AgendaRow(event: event, isSelected: calendar.focusedEvent?.id == event.id) {
                            withAnimation(IslandMotion.tab) { calendar.selectedID = event.id }
                        }
                    }
                }
            }
            .padding(.bottom, IslandSpacing.m)
        }
        .scrollIndicators(.hidden)
        // Fade rows out at the bottom edge instead of cutting them off.
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: IslandSpacing.m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgendaRow: View {
    let event: CalendarEvent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            HStack(spacing: IslandSpacing.s + 2) {
                Capsule()
                    .fill(Color(nsColor: event.calendarColor))
                    .frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(CalendarFormat.timeRange(for: event))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if event.isOngoing(at: Date()) {
                    Text("Now")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
            }
            .padding(.horizontal, IslandSpacing.s)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.white.opacity(isSelected ? 0.12 : 0)))
            .contentShape(shape)
        }
        .buttonStyle(GlassPressStyle())
        .hoverHighlight(shape)
        .animation(IslandMotion.hover, value: isSelected)
        .accessibilityLabel("\(event.title), \(CalendarFormat.timeRange(for: event))")
    }
}

// MARK: - Empty / permission states

private struct CalendarMessage: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var isActionDisabled = false
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: IslandSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 300)
            if let actionTitle {
                GlassChip(
                    title: actionTitle,
                    isSelected: true,
                    tint: IslandPalette.calendar,
                    isDisabled: isActionDisabled,
                    action: action
                )
                .padding(.top, IslandSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
