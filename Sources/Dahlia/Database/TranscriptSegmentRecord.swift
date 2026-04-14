import Foundation
import GRDB

/// 文字起こしセグメントを表す GRDB レコード。
struct TranscriptSegmentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcript_segments"

    var id: UUID
    var meetingId: UUID
    var startTime: Date
    var endTime: Date?
    var text: String
    var isConfirmed: Bool
    var speakerLabel: String?
}

extension TranscriptSegmentRecord {
    /// TranscriptSegment から TranscriptSegmentRecord を生成する。
    init(from segment: TranscriptSegment, meetingId: UUID) {
        self.id = segment.id
        self.meetingId = meetingId
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.text = segment.text
        self.isConfirmed = segment.isConfirmed
        self.speakerLabel = segment.speakerLabel
    }
}
