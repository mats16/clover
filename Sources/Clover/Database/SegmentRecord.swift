import Foundation
import GRDB

/// 文字起こしセグメントを表す GRDB レコード。
struct SegmentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "segments"

    var id: UUID
    var transcriptionId: UUID
    var startTime: Date
    var endTime: Date?
    var text: String
    var isConfirmed: Bool
    var speakerLabel: String?
}

extension SegmentRecord {
    /// TranscriptSegment から SegmentRecord を生成する。
    init(from segment: TranscriptSegment, transcriptionId: UUID) {
        self.id = segment.id
        self.transcriptionId = transcriptionId
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.text = segment.text
        self.isConfirmed = segment.isConfirmed
        self.speakerLabel = segment.speakerLabel
    }
}
