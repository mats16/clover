import SwiftUI

struct HomeOverviewView: View {
    @StateObject private var calendarStore = GoogleCalendarStore.shared
    @Environment(\.openSettings) private var openSettings
    let onSelectEvent: (GoogleCalendarEvent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .task {
            await calendarStore.restoreSessionIfNeeded()
            await calendarStore.refreshIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.home)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

            Text(L10n.googleCalendarHomeDescription)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch calendarStore.state {
        case .unconfigured:
            HomeStatusCard(
                title: L10n.googleCalendarClientIDMissingTitle,
                message: L10n.googleCalendarClientIDMissingMessage,
                actionTitle: nil,
                action: nil
            )
        case .signedOut:
            HomeStatusCard(
                title: L10n.googleCalendarSignInRequiredTitle,
                message: L10n.googleCalendarSignInRequiredMessage,
                actionTitle: L10n.settings,
                action: { openSettings() }
            )
        case .needsCalendarSelection:
            HomeStatusCard(
                title: L10n.googleCalendarSelectionRequiredTitle,
                message: L10n.googleCalendarSelectionRequiredMessage,
                actionTitle: L10n.settings,
                action: { openSettings() }
            )
        case .loading:
            ProgressView(L10n.googleCalendarLoading)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        case .failed:
            HomeStatusCard(
                title: L10n.googleCalendarLoadFailedTitle,
                message: calendarStore.lastErrorMessage ?? L10n.googleCalendarUnexpectedResponse,
                actionTitle: L10n.googleCalendarRetry,
                action: {
                    Task {
                        await calendarStore.refreshIfNeeded(force: true)
                    }
                }
            )
        case .loaded:
            if calendarStore.upcomingEvents.isEmpty {
                HomeStatusCard(
                    title: L10n.googleCalendarNoUpcomingEventsTitle,
                    message: L10n.googleCalendarNoUpcomingEventsMessage,
                    actionTitle: nil,
                    action: nil
                )
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(eventSections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)

                            VStack(spacing: 10) {
                                ForEach(section.events) { event in
                                    HomeCalendarEventRow(event: event, onSelect: {
                                        onSelectEvent(event)
                                    })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var eventSections: [HomeEventSection] {
        let grouped = Dictionary(grouping: calendarStore.upcomingEvents) {
            Calendar.current.startOfDay(for: $0.startDate)
        }

        return grouped.keys.sorted().map { date in
            let title: String = if Calendar.current.isDateInToday(date) {
                L10n.today
            } else if Calendar.current.isDateInTomorrow(date) {
                L10n.tomorrow
            } else {
                date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            }

            return HomeEventSection(
                id: date.formatted(.iso8601.year().month().day()),
                title: title,
                events: grouped[date] ?? []
            )
        }
    }
}

private struct HomeEventSection: Identifiable {
    let id: String
    let title: String
    let events: [GoogleCalendarEvent]
}

private struct HomeCalendarEventRow: View {
    let event: GoogleCalendarEvent
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .fill(event.calendarColorHex.map(Color.init(hex:)) ?? Color.accentColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 10) {
                        Text(timeLabel)
                        if event.meetingURL != nil {
                            Label(L10n.googleCalendarMeetingLinkAvailable, systemImage: "video")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var timeLabel: String {
        if event.isAllDay {
            return L10n.googleCalendarAllDay
        }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(end)"
    }
}

private struct HomeStatusCard: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }
}
