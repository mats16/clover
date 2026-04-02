import Foundation
import GRDB

/// 文字起こしセッションを表す GRDB レコード。
/// 各プロジェクトフォルダの DB に格納されるため、projectId は不要。
struct TranscriptionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transcriptions"

    var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
}
