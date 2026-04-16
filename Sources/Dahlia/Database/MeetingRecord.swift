import Foundation
import GRDB

/// ミーティングの状態。
enum MeetingStatus: String, Codable, DatabaseValueConvertible {
    case transcriptNotFound = "TRANSCRIPT_NOT_FOUND"
    case recording = "RECORDING"
    case processingTranscript = "PROCESSING_TRANSCRIPT"
    case ready = "READY"
}

/// ミーティングセッションを表す GRDB レコード。
struct MeetingRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "meetings"

    var id: UUID
    var projectId: UUID
    var name: String
    var status: MeetingStatus = .transcriptNotFound
    var duration: TimeInterval?
    var bulletPointSummary: String?
    var createdAt: Date
    var updatedAt: Date

    var isRecording: Bool { status == .recording }
}
