import Foundation
import GRDB

/// 文字起こしセッションを表す GRDB レコード。
struct TranscriptionRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "transcripts"

    var id: UUID
    var projectId: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var summaryCreated: Bool
    var filePath: String?
}
