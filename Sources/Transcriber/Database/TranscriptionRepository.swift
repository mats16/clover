import Foundation
import GRDB

/// 文字起こし・セグメントの DB クエリを集約するリポジトリ。
/// プロジェクトフォルダの DatabaseQueue を受け取って動作する。
@MainActor
final class TranscriptionRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Transcriptions

    func fetchAllTranscriptions() throws -> [TranscriptionRecord] {
        try dbQueue.read { db in
            try TranscriptionRecord
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }
    }

    func renameTranscription(id: UUID, newTitle: String) throws {
        try dbQueue.write { db in
            if var record = try TranscriptionRecord.fetchOne(db, key: id) {
                record.title = newTitle
                try record.update(db)
            }
        }
    }

    func deleteTranscription(id: UUID) throws {
        try dbQueue.write { db in
            _ = try TranscriptionRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Segments

    func fetchSegments(forTranscriptionId transcriptionId: UUID) throws -> [SegmentRecord] {
        try dbQueue.read { db in
            try SegmentRecord
                .filter(Column("transcriptionId") == transcriptionId)
                .order(Column("startTime").asc)
                .fetchAll(db)
        }
    }

    func fetchSegmentIds(forTranscriptionId transcriptionId: UUID) throws -> Set<UUID> {
        try dbQueue.read { db in
            let ids = try SegmentRecord
                .select(Column("id"))
                .filter(Column("transcriptionId") == transcriptionId)
                .asRequest(of: UUID.self)
                .fetchAll(db)
            return Set(ids)
        }
    }
}
