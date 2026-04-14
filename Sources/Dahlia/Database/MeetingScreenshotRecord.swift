import Foundation
import GRDB

/// スクリーンショットを表す GRDB レコード。
struct MeetingScreenshotRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_screenshots"

    var id: UUID
    var meetingId: UUID
    var capturedAt: Date
    var imageData: Data
}
