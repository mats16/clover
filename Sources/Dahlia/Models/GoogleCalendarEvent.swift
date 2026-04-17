import Foundation

struct GoogleCalendarEvent: Identifiable, Equatable {
    let id: String
    let calendarID: String
    let calendarName: String
    let calendarColorHex: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let meetingURL: URL?
}
