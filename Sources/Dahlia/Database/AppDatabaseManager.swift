import Foundation
import GRDB

/// アプリ全体で単一の SQLite データベースを管理する。
/// `~/Library/Application Support/Dahlia/dahlia.sqlite` に配置する。
final class AppDatabaseManager: Sendable {
    let dbQueue: DatabaseQueue

    /// アプリケーションサポートディレクトリに DB を作成・オープンする。
    init() throws {
        let dbURL = Self.databaseURL
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        dbQueue = try DatabaseQueue(path: dbURL.path)
        try Self.migrator.migrate(dbQueue)
    }

    /// DB ファイルの URL。
    nonisolated static var databaseURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dahlia")
            .appendingPathComponent("dahlia.sqlite")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_consolidatedSchema") { db in
            try db.create(table: "vaults") { t in
                t.primaryKey("id", .blob)
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime).notNull()
            }

            try db.create(table: "projects") { t in
                t.primaryKey("id", .blob)
                t.column("vaultId", .blob).notNull()
                    .references("vaults", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["vaultId", "name"])
            }
            try db.create(
                index: "projects_on_vaultId",
                on: "projects",
                columns: ["vaultId"]
            )

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

        migrator.registerMigration("v2_notesAndScreenshots") { db in
            try db.create(table: "notes") { t in
                t.primaryKey("id", .blob)
                t.column("transcriptionId", .blob).notNull()
                    .references("transcripts", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "notes_on_transcriptionId",
                on: "notes",
                columns: ["transcriptionId"]
            )

            try db.create(table: "screenshots") { t in
                t.primaryKey("id", .blob)
                t.column("transcriptionId", .blob).notNull()
                    .references("transcripts", onDelete: .cascade)
                t.column("capturedAt", .datetime).notNull()
                t.column("imageData", .blob).notNull()
            }
            try db.create(
                index: "screenshots_on_transcriptionId",
                on: "screenshots",
                columns: ["transcriptionId"]
            )
        }

        migrator.registerMigration("v3_sidebarIndexes") { db in
            try db.create(
                index: "transcripts_on_projectId_startedAt",
                on: "transcripts",
                columns: ["projectId", "startedAt"]
            )
        }

        return migrator
    }
}
