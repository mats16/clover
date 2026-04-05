import Foundation
import GRDB

/// 文字起こし・セグメント・プロジェクトの DB クエリを集約するリポジトリ。
@MainActor
final class TranscriptionRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Projects

    /// 全プロジェクトを name 順で取得する。
    func fetchAllProjects() throws -> [ProjectRecord] {
        try dbQueue.read { db in
            try ProjectRecord.order(Column("name").asc).fetchAll(db)
        }
    }

    /// 指定名のプロジェクトを取得し、存在しなければ作成して返す。
    func fetchOrCreateProject(name: String) throws -> ProjectRecord {
        try dbQueue.write { db in
            if let existing = try ProjectRecord
                .filter(Column("name") == name)
                .fetchOne(db) {
                return existing
            }
            let record = ProjectRecord(id: .v7(), name: name, createdAt: Date())
            try record.insert(db)
            return record
        }
    }

    /// 複数の name を一括で INSERT OR IGNORE する。
    func upsertProjects(names: [String]) throws {
        guard !names.isEmpty else { return }
        try dbQueue.write { db in
            try ProjectRecord.upsertAll(names: names, in: db)
        }
    }

    /// name が指定プレフィクスで始まるレコードを一括リネームする。
    func renameProjectsByPrefix(oldPrefix: String, newPrefix: String) throws {
        try dbQueue.write { db in
            try ProjectRecord.renameByPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix, in: db)
        }
    }

    func deleteProject(id: UUID) throws {
        try dbQueue.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id)
        }
    }

    /// 指定プロジェクトとその配下を一括削除する。
    func deleteProjectsByPrefix(name: String) throws {
        try dbQueue.write { db in
            _ = try ProjectRecord.deleteByPrefix(name, in: db)
        }
    }

    // MARK: - Transcriptions

    func fetchTranscriptions(forProjectId projectId: UUID) throws -> [TranscriptionRecord] {
        try dbQueue.read { db in
            try TranscriptionRecord
                .filter(Column("projectId") == projectId)
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }
    }

    func fetchTranscription(id: UUID) throws -> TranscriptionRecord? {
        try dbQueue.read { db in
            try TranscriptionRecord.fetchOne(db, key: id)
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

    func markSummaryCreated(id: UUID) throws {
        try dbQueue.write { db in
            if var record = try TranscriptionRecord.fetchOne(db, key: id) {
                record.summaryCreated = true
                try record.update(db)
            }
        }
    }

    func updateTranscriptFilePath(id: UUID, path: String) throws {
        try dbQueue.write { db in
            if var record = try TranscriptionRecord.fetchOne(db, key: id) {
                record.filePath = path
                try record.update(db)
            }
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
