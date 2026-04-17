import SwiftUI

struct CalendarSettingsView: View {
    @ObservedObject private var calendarStore = GoogleCalendarStore.shared

    var body: some View {
        SettingsPage {
            SettingsSection(
                title: L10n.googleCalendar,
                description: L10n.googleCalendarSettingsDescription
            ) {
                SettingsCard {
                    connectionRow

                    if let message = calendarStore.lastErrorMessage {
                        Divider()

                        SettingsStatusMessage(
                            text: message,
                            systemImage: "exclamationmark.triangle",
                            tint: .orange
                        )
                        .padding(20)
                    }
                }
            }

            if calendarStore.account != nil {
                SettingsSection(
                    title: L10n.googleCalendarDisplayCalendars,
                    description: L10n.googleCalendarDisplayCalendarsDescription
                ) {
                    SettingsCard {
                        if calendarStore.isBusy, calendarStore.availableCalendars.isEmpty {
                            ProgressView(L10n.googleCalendarLoading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        } else if calendarStore.availableCalendars.isEmpty {
                            Text(L10n.googleCalendarNoCalendars)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        } else {
                            ForEach(Array(calendarStore.availableCalendars.enumerated()), id: \.element.id) { index, calendar in
                                CalendarSelectionRow(
                                    calendar: calendar,
                                    isSelected: calendarStore.selectedCalendarIDs.contains(calendar.id)
                                ) {
                                    calendarStore.toggleCalendarSelection(id: calendar.id)
                                }

                                if index < calendarStore.availableCalendars.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await calendarStore.refreshIfNeeded()
        }
    }

    private var connectionRow: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(calendarStore.account?.displayName ?? L10n.googleCalendarNotConnected)
                    .font(.headline)

                Text(accountSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButton
        }
        .padding(20)
    }

    @ViewBuilder
    private var actionButton: some View {
        if calendarStore.account == nil {
            Button(L10n.googleCalendarConnect) {
                Task {
                    await calendarStore.signIn()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!calendarStore.isConfigured || calendarStore.isBusy)
        } else {
            Button(L10n.googleCalendarDisconnect) {
                Task {
                    await calendarStore.disconnect()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!calendarStore.isConfigured || calendarStore.isBusy)
        }
    }

    private var accountSubtitle: String {
        if !calendarStore.isConfigured {
            return L10n.googleCalendarClientIDMissingMessage
        }

        if let account = calendarStore.account {
            return account.email.isEmpty ? L10n.googleCalendarConnected : account.email
        }

        return L10n.googleCalendarConnectDescription
    }
}

private struct CalendarSelectionRow: View {
    let calendar: GoogleCalendarListItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 16) {
                Circle()
                    .fill(calendar.colorHex.map(Color.init(hex:)) ?? Color.accentColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(calendar.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if calendar.isPrimary {
                        Text(L10n.googleCalendarPrimaryCalendar)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
