import Foundation
import GRDB

/// 手動ノートを表す GRDB レコード。
struct NoteRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"

    var id: UUID
    var transcriptionId: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
}
