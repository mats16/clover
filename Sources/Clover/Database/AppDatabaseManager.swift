import Foundation
import GRDB

/// アプリ全体で単一の SQLite データベースを管理する。
/// 保管庫ルートに `.transcriptions.sqlite` を作成・オープンする。
final class AppDatabaseManager: Sendable {
    let dbQueue: DatabaseQueue

    init(vaultURL: URL) throws {
        let dbPath = vaultURL.appendingPathComponent(".transcriptions.sqlite")
        dbQueue = try DatabaseQueue(path: dbPath.path)
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_consolidatedSchema") { db in
            try db.create(table: "projects") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull().unique()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "transcripts") { t in
                t.primaryKey("id", .blob)
                t.column("projectId", .blob).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("summaryCreated", .boolean).notNull().defaults(to: false)
                t.column("filePath", .text)
            }
            try db.create(
                index: "transcripts_on_projectId",
                on: "transcripts",
                columns: ["projectId"]
            )

            try db.create(table: "segments") { t in
                t.primaryKey("id", .blob)
                t.column("transcriptionId", .blob).notNull()
                    .references("transcripts", onDelete: .cascade)
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("text", .text).notNull()
                t.column("isConfirmed", .boolean).notNull().defaults(to: false)
                t.column("speakerLabel", .text)
            }
            try db.create(
                index: "segments_on_transcriptionId",
                on: "segments",
                columns: ["transcriptionId"]
            )
            try db.create(
                index: "segments_on_transcriptionId_startTime",
                on: "segments",
                columns: ["transcriptionId", "startTime"]
            )
        }

        return migrator
    }
}
