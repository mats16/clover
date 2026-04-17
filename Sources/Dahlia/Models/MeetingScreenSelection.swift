import Foundation

enum MeetingScreenSelection: Equatable {
    case persisted(UUID)
    case draft(UUID)

    var meetingId: UUID? {
        guard case let .persisted(id) = self else { return nil }
        return id
    }

    var draftId: UUID? {
        guard case let .draft(id) = self else { return nil }
        return id
    }
}
