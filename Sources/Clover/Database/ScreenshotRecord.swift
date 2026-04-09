import Foundation
import GRDB

/// スクリーンショットを表す GRDB レコード。
struct ScreenshotRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "screenshots"

    var id: UUID
    var transcriptionId: UUID
    var capturedAt: Date
    var imageData: Data
}
