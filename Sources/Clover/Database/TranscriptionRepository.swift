import Foundation
import GRDB

/// 文字起こし・セグメント・プロジェクト・保管庫の DB クエリを集約するリポジトリ。
@MainActor
final class TranscriptionRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Vaults

    /// 全保管庫を最終オープン日時の降順で取得する。
    func fetchAllVaults() throws -> [VaultRecord] {
        try dbQueue.read { db in
            try VaultRecord.order(Column("lastOpenedAt").desc).fetchAll(db)
        }
    }

    /// 最後にオープンした保管庫を取得する。
    func fetchLastOpenedVault() throws -> VaultRecord? {
        try dbQueue.read { db in
            try VaultRecord.order(Column("lastOpenedAt").desc).fetchOne(db)
        }
    }

    /// 保管庫を登録する。
    func insertVault(_ vault: VaultRecord) throws {
        try dbQueue.write { db in
            try vault.insert(db)
        }
    }

    /// 保管庫を登録解除する（関連プロジェクト・文字起こしもカスケード削除）。
    func deleteVault(id: UUID) throws {
        try dbQueue.write { db in
            _ = try VaultRecord.deleteOne(db, key: id)
        }
    }

    /// 保管庫の最終オープン日時を更新する。
    func updateVaultLastOpened(id: UUID) throws {
        try dbQueue.write { db in
            if var record = try VaultRecord.fetchOne(db, key: id) {
                record.lastOpenedAt = Date()
                try record.update(db)
            }
        }
    }

    // MARK: - Projects

    /// 指定保管庫のプロジェクトを name 順で取得する。
    func fetchAllProjects(vaultId: UUID) throws -> [ProjectRecord] {
        try dbQueue.read { db in
            try ProjectRecord
                .filter(Column("vaultId") == vaultId)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// 指定名のプロジェクトを取得し、存在しなければ作成して返す。
    func fetchOrCreateProject(name: String, vaultId: UUID) throws -> ProjectRecord {
        try dbQueue.write { db in
            if let existing = try ProjectRecord
                .filter(Column("vaultId") == vaultId)
                .filter(Column("name") == name)
                .fetchOne(db) {
                return existing
            }
            let record = ProjectRecord(id: .v7(), vaultId: vaultId, name: name, createdAt: Date())
            try record.insert(db)
            return record
        }
    }

    /// 複数の name を一括で INSERT OR IGNORE する。
    func upsertProjects(names: [String], vaultId: UUID) throws {
        guard !names.isEmpty else { return }
        try dbQueue.write { db in
            try ProjectRecord.upsertAll(names: names, vaultId: vaultId, in: db)
        }
    }

    /// name が指定プレフィクスで始まるレコードを一括リネームする。
    func renameProjectsByPrefix(oldPrefix: String, newPrefix: String, vaultId: UUID) throws {
        try dbQueue.write { db in
            try ProjectRecord.renameByPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix, vaultId: vaultId, in: db)
        }
    }

    func deleteProject(id: UUID) throws {
        try dbQueue.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id)
        }
    }

    /// 指定プロジェクトとその配下を一括削除する。
    func deleteProjectsByPrefix(name: String, vaultId: UUID) throws {
        try dbQueue.write { db in
            _ = try ProjectRecord.deleteByPrefix(name, vaultId: vaultId, in: db)
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

    // MARK: - Screenshots

    func fetchScreenshots(forTranscriptionId transcriptionId: UUID) throws -> [ScreenshotRecord] {
        try dbQueue.read { db in
            try ScreenshotRecord
                .filter(Column("transcriptionId") == transcriptionId)
                .order(Column("capturedAt").asc)
                .fetchAll(db)
        }
    }

    func deleteScreenshot(id: UUID) throws {
        try dbQueue.write { db in
            _ = try ScreenshotRecord.deleteOne(db, key: id)
        }
    }

    /// 文字起こし詳細をまとめて取得する（単一トランザクション）。
    struct TranscriptionDetail {
        let transcription: TranscriptionRecord?
        let segments: [SegmentRecord]
        let screenshots: [ScreenshotRecord]
    }

    func fetchTranscriptionDetail(id transcriptionId: UUID) throws -> TranscriptionDetail {
        try dbQueue.read { db in
            let transcription = try TranscriptionRecord.fetchOne(db, key: transcriptionId)
            let segments = try SegmentRecord
                .filter(Column("transcriptionId") == transcriptionId)
                .order(Column("startTime").asc)
                .fetchAll(db)
            let screenshots = try ScreenshotRecord
                .filter(Column("transcriptionId") == transcriptionId)
                .order(Column("capturedAt").asc)
                .fetchAll(db)
            return TranscriptionDetail(transcription: transcription, segments: segments, screenshots: screenshots)
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
