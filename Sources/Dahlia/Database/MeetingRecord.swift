import Foundation
import GRDB

/// ミーティングセッションを表す GRDB レコード。
struct MeetingRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "meetings"

    var id: UUID
    var projectId: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
}
