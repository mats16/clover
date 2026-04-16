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

            try db.create(table: "meetings") { t in
                t.primaryKey("id", .blob)
                t.column("projectId", .blob).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("name", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: MeetingStatus.transcriptNotFound.rawValue)
                t.column("duration", .double)
                t.column("bulletPointSummary", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "meetings_on_projectId",
                on: "meetings",
                columns: ["projectId"]
            )

            try db.create(table: "transcript_segments") { t in
                t.primaryKey("id", .blob)
                t.column("meetingId", .blob).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("text", .text).notNull()
                t.column("isConfirmed", .boolean).notNull().defaults(to: false)
                t.column("speakerLabel", .text)
            }
            try db.create(
                index: "transcript_segments_on_meetingId",
                on: "transcript_segments",
                columns: ["meetingId"]
            )
            try db.create(
                index: "transcript_segments_on_meetingId_startTime",
                on: "transcript_segments",
                columns: ["meetingId", "startTime"]
            )

            // tags マスタテーブル
            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("colorHex", .text).notNull().defaults(to: "#808080")
                t.column("createdAt", .datetime).notNull()
            }

            // meeting_tags 中間テーブル
            try db.create(table: "meeting_tags") { t in
                t.column("meetingId", .blob).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("tagId", .integer).notNull()
                    .references("tags", onDelete: .cascade)
                t.primaryKey(["meetingId", "tagId"])
            }
            try db.create(
                index: "meeting_tags_on_tagId",
                on: "meeting_tags",
                columns: ["tagId"]
            )
        }

        migrator.registerMigration("v2_notesAndScreenshots") { db in
            try db.create(table: "meeting_notes") { t in
                t.primaryKey("meetingId", .blob)
                    .references("meetings", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "meeting_screenshots") { t in
                t.primaryKey("id", .blob)
                t.column("meetingId", .blob).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("capturedAt", .datetime).notNull()
                t.column("imageData", .blob).notNull()
            }
            try db.create(
                index: "meeting_screenshots_on_meetingId",
                on: "meeting_screenshots",
                columns: ["meetingId"]
            )
        }

        migrator.registerMigration("v3_sidebarIndexes") { db in
            try db.create(
                index: "meetings_on_projectId_createdAt",
                on: "meetings",
                columns: ["projectId", "createdAt"]
            )
        }

        migrator.registerMigration("v4_addMissingOnDisk") { db in
            try db.alter(table: "projects") { t in
                t.add(column: "missingOnDisk", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v5_meetingSummaries") { db in
            try db.create(table: "meeting_summaries") { t in
                t.primaryKey("id", .blob)
                t.column("meetingId", .blob).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("summary", .text).notNull()
                t.column("tags", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(
                index: "meeting_summaries_on_meetingId",
                on: "meeting_summaries",
                columns: ["meetingId"],
                unique: true
            )
        }

        return migrator
    }
}
