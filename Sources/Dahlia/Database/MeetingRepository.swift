import Foundation
import GRDB

/// ミーティング・セグメント・プロジェクト・保管庫の DB クエリを集約するリポジトリ。
@MainActor
final class MeetingRepository {
    private static let generatedSummaryTagColorHex = "#808080"

    private let dbQueue: DatabaseQueue

    nonisolated init(dbQueue: DatabaseQueue) {
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

    /// 保管庫を登録解除する（関連プロジェクト・ミーティングもカスケード削除）。
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

    /// 指定プレフィクスに一致するプロジェクトの missingOnDisk フラグをクリアする。
    func clearProjectsMissing(prefix: String, vaultId: UUID) throws {
        try dbQueue.write { db in
            try ProjectRecord.setMissingByPrefix(prefix, missing: false, vaultId: vaultId, in: db)
        }
    }

    // MARK: - Meetings

    func fetchMeetings(forProjectId projectId: UUID) throws -> [MeetingRecord] {
        try dbQueue.read { db in
            try MeetingRecord
                .filter(Column("projectId") == projectId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchMeeting(id: UUID) throws -> MeetingRecord? {
        try dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: id)
        }
    }

    func renameMeeting(id: UUID, newName: String) throws {
        try dbQueue.write { db in
            if var record = try MeetingRecord.fetchOne(db, key: id) {
                record.name = newName
                try record.update(db)
            }
        }
    }

    func deleteMeeting(id: UUID) throws {
        try dbQueue.write { db in
            _ = try MeetingRecord.deleteOne(db, key: id)
        }
    }

    /// 複数のミーティングを一括削除する。
    func deleteMeetings(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            _ = try MeetingRecord.filter(ids.contains(Column("id"))).deleteAll(db)
        }
    }

    func moveMeeting(id: UUID, toProjectId: UUID?) throws {
        try dbQueue.write { db in
            if var record = try MeetingRecord.fetchOne(db, key: id) {
                record.projectId = toProjectId
                try record.update(db)
            }
        }
    }

    /// 複数のミーティングを一括移動する。
    func moveMeetings(ids: Set<UUID>, toProjectId: UUID?) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            _ = try MeetingRecord
                .filter(ids.contains(Column("id")))
                .updateAll(db, Column("projectId").set(to: toProjectId))
        }
    }

    func applyGeneratedSummary(
        toMeetingId meetingId: UUID,
        title: String,
        summary: String,
        tags: [String],
        actionItems: [SummaryActionItem]
    ) throws {
        try dbQueue.write { db in
            guard try MeetingRecord.fetchOne(db, key: meetingId) != nil else { return }

            let existingSummary = try SummaryRecord.fetchOne(db, key: meetingId)
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = SummaryRecord(
                meetingId: meetingId,
                title: trimmedTitle.isEmpty ? (existingSummary?.title ?? "") : trimmedTitle,
                summary: summary,
                createdAt: existingSummary?.createdAt ?? Date()
            )
            try record.save(db)

            try replaceActionItems(forMeetingId: meetingId, with: actionItems, in: db)

            let tagNames = tags.filter { !$0.isEmpty }
            if !tagNames.isEmpty {
                let existingTags = try TagRecord
                    .filter(tagNames.contains(Column("name")))
                    .fetchAll(db)
                let existingByName = Dictionary(uniqueKeysWithValues: existingTags.compactMap { tag in
                    tag.id.map { (tag.name, $0) }
                })

                for name in tagNames {
                    let tagId: Int64
                    if let existingId = existingByName[name] {
                        tagId = existingId
                    } else {
                        let newTag = TagRecord(
                            name: name,
                            colorHex: Self.generatedSummaryTagColorHex,
                            createdAt: Date()
                        )
                        try newTag.insert(db)
                        tagId = db.lastInsertedRowID
                    }

                    try db.execute(
                        sql: "INSERT OR IGNORE INTO meeting_tags (meetingId, tagId) VALUES (?, ?)",
                        arguments: [meetingId, tagId]
                    )
                }
            }
        }
    }

    // MARK: - Tags

    func addTag(name: String, toMeetingId meetingId: UUID, colorHex: String) throws {
        try dbQueue.write { db in
            let tagId: Int64
            if let existing = try TagRecord.filter(Column("name") == name).fetchOne(db) {
                guard let existingId = existing.id else { return }
                tagId = existingId
            } else {
                let newTag = TagRecord(name: name, colorHex: colorHex, createdAt: Date())
                try newTag.insert(db)
                tagId = db.lastInsertedRowID
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO meeting_tags (meetingId, tagId) VALUES (?, ?)",
                arguments: [meetingId, tagId]
            )
        }
    }

    /// 孤立したタグマスタも自動削除する。
    func removeTag(name: String, fromMeetingId meetingId: UUID) throws {
        try dbQueue.write { db in
            guard let tag = try TagRecord.filter(Column("name") == name).fetchOne(db),
                  let tagId = tag.id else { return }
            _ = try MeetingTagRecord
                .filter(Column("meetingId") == meetingId && Column("tagId") == tagId)
                .deleteAll(db)
            let count = try MeetingTagRecord.filter(Column("tagId") == tagId).fetchCount(db)
            if count == 0 {
                _ = try TagRecord.deleteOne(db, key: tagId)
            }
        }
    }

    func fetchAllTags() throws -> [TagRecord] {
        try dbQueue.read { db in
            try TagRecord.order(Column("name").asc).fetchAll(db)
        }
    }

    func fetchTagsForMeeting(id meetingId: UUID) throws -> [TagRecord] {
        try dbQueue.read { db in
            try TagRecord.fetchAll(
                db,
                sql: """
                SELECT t.*
                FROM tags t
                INNER JOIN meeting_tags mt ON mt.tagId = t.id
                WHERE mt.meetingId = ?
                ORDER BY t.name ASC
                """,
                arguments: [meetingId]
            )
        }
    }

    func updateTagColor(id: Int64, colorHex: String) throws {
        try dbQueue.write { db in
            if var tag = try TagRecord.fetchOne(db, key: id) {
                tag.colorHex = colorHex
                try tag.update(db)
            }
        }
    }

    // MARK: - Segments

    func fetchSegments(forMeetingId meetingId: UUID) throws -> [TranscriptSegmentRecord] {
        try dbQueue.read { db in
            try TranscriptSegmentRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("startTime").asc)
                .fetchAll(db)
        }
    }

    func fetchSegmentIds(forMeetingId meetingId: UUID) throws -> Set<UUID> {
        try dbQueue.read { db in
            let ids = try TranscriptSegmentRecord
                .select(Column("id"))
                .filter(Column("meetingId") == meetingId)
                .asRequest(of: UUID.self)
                .fetchAll(db)
            return Set(ids)
        }
    }

    // MARK: - Notes

    /// 指定ミーティングに紐づくノートを取得する（1 meeting = 1 note）。
    func fetchNote(forMeetingId meetingId: UUID) throws -> MeetingNoteRecord? {
        try dbQueue.read { db in
            try MeetingNoteRecord.fetchOne(db, key: meetingId)
        }
    }

    /// ノートを保存する（insert or update）。
    nonisolated func upsertNote(_ note: MeetingNoteRecord) throws {
        try dbQueue.write { db in
            try note.save(db)
        }
    }

    /// ノートを削除する。
    func deleteNote(meetingId: UUID) throws {
        try dbQueue.write { db in
            _ = try MeetingNoteRecord.deleteOne(db, key: meetingId)
        }
    }

    // MARK: - Screenshots

    func fetchScreenshots(forMeetingId meetingId: UUID) throws -> [MeetingScreenshotRecord] {
        try dbQueue.read { db in
            try MeetingScreenshotRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("capturedAt").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Action Items

    private nonisolated static func actionItemsRequest(meetingId: UUID) -> QueryInterfaceRequest<ActionItemRecord> {
        ActionItemRecord
            .filter(Column("meetingId") == meetingId)
            .order(Column("isCompleted").asc, Column("title").asc, Column("assignee").asc, Column("id").asc)
    }

    func fetchActionItems(forMeetingId meetingId: UUID) throws -> [ActionItemRecord] {
        try dbQueue.read { db in
            try Self.actionItemsRequest(meetingId: meetingId).fetchAll(db)
        }
    }

    func setActionItemCompleted(id: UUID, isCompleted: Bool) throws {
        try dbQueue.write { db in
            guard var record = try ActionItemRecord.fetchOne(db, key: id) else { return }
            record.isCompleted = isCompleted
            try record.update(db)
        }
    }

    func setActionItemAssignee(id: UUID, assignee: String) throws {
        try dbQueue.write { db in
            guard var record = try ActionItemRecord.fetchOne(db, key: id) else { return }
            record.assignee = SummaryActionItem.normalize(assignee)
            try record.update(db)
        }
    }

    func deleteActionItem(id: UUID) throws {
        try dbQueue.write { db in
            _ = try ActionItemRecord.deleteOne(db, key: id)
        }
    }

    func deleteScreenshot(id: UUID) throws {
        try dbQueue.write { db in
            _ = try MeetingScreenshotRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Summaries

    func fetchSummary(forMeetingId meetingId: UUID) throws -> SummaryRecord? {
        try dbQueue.read { db in
            try SummaryRecord.fetchOne(db, key: meetingId)
        }
    }

    /// サマリーを保存する（insert or update）。
    nonisolated func upsertSummary(_ summary: SummaryRecord) throws {
        try dbQueue.write { db in
            try summary.save(db)
        }
    }

    // MARK: - Composite

    /// ミーティング詳細をまとめて取得する（単一トランザクション）。
    struct MeetingDetail {
        let meeting: MeetingRecord?
        let segments: [TranscriptSegmentRecord]
        let screenshots: [MeetingScreenshotRecord]
        let note: MeetingNoteRecord?
        let summary: SummaryRecord?
        let actionItems: [ActionItemRecord]
    }

    nonisolated func fetchMeetingDetail(id meetingId: UUID) throws -> MeetingDetail {
        try dbQueue.read { db in
            let meeting = try MeetingRecord.fetchOne(db, key: meetingId)
            let segments = try TranscriptSegmentRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("startTime").asc)
                .fetchAll(db)
            let screenshots = try MeetingScreenshotRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("capturedAt").asc)
                .fetchAll(db)
            let note = try MeetingNoteRecord.fetchOne(db, key: meetingId)
            let summary = try SummaryRecord.fetchOne(db, key: meetingId)
            let actionItems = try Self.actionItemsRequest(meetingId: meetingId).fetchAll(db)
            return MeetingDetail(
                meeting: meeting,
                segments: segments,
                screenshots: screenshots,
                note: note,
                summary: summary,
                actionItems: actionItems
            )
        }
    }

    private func replaceActionItems(
        forMeetingId meetingId: UUID,
        with actionItems: [SummaryActionItem],
        in db: Database
    ) throws {
        let existingActionItems = try ActionItemRecord
            .filter(Column("meetingId") == meetingId)
            .order(Column("id").asc)
            .fetchAll(db)
        var existingByKey = Dictionary(grouping: existingActionItems, by: \.persistenceKey)

        let normalizedActionItems = actionItems.compactMap { item -> SummaryActionItem? in
            let normalizedTitle = SummaryActionItem.normalize(item.title)
            guard !normalizedTitle.isEmpty else { return nil }
            return SummaryActionItem(
                title: normalizedTitle,
                assignee: SummaryActionItem.normalize(item.assignee)
            )
        }

        _ = try ActionItemRecord
            .filter(Column("meetingId") == meetingId)
            .deleteAll(db)

        for item in normalizedActionItems {
            let key = item.persistenceKey
            let preservedCompletion: Bool
            if var records = existingByKey[key], let existingRecord = records.first {
                preservedCompletion = existingRecord.isCompleted
                records.removeFirst()
                existingByKey[key] = records
            } else {
                preservedCompletion = false
            }

            let record = ActionItemRecord(
                id: .v7(),
                meetingId: meetingId,
                title: item.title,
                assignee: item.assignee,
                isCompleted: preservedCompletion
            )
            try record.insert(db)
        }
    }

}
