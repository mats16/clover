import Foundation

struct DraftMeeting: Equatable {
    var id: UUID
    var title: String
    var linkedCalendarEvent: GoogleCalendarEvent?
    var projectURL: URL?
    var projectId: UUID?
    var projectName: String?
}
