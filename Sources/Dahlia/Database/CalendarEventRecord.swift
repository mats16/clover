import Foundation
import GRDB

struct CalendarEventRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "calendar_events"

    var id: Int64? = nil
    var meetingId: UUID
    var createdAt: Date
    var updatedAt: Date
    var platform: String
    var platformId: String
    var description: String
    var icalUid: String?
    var start: Date
    var end: Date
    var meetingUrl: String?
}
