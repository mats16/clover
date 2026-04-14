import Foundation
import GRDB

/// ミーティング要約を表す GRDB レコード。
struct MeetingSummaryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_summaries"

    var id: UUID
    var meetingId: UUID
    var title: String
    var summary: String
    var tags: String
    var createdAt: Date
}
