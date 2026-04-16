import Foundation
import GRDB

/// アプリ全体で単一の SQLite データベースを管理する。
/// `~/Library/Application Support/Dahlia/dahlia.sqlite` に配置する。
final class AppDatabaseManager: Sendable {
    let dbQueue: DatabaseQueue

    /// アプリケーションサポートディレクトリに DB を作成・オープンする。
    convenience init() throws {
        try self.init(path: Self.databaseURL.path)
    }

    init(path: String) throws {
        if path != ":memory:" {
            let dbURL = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    /// DB ファイルの URL。
    nonisolated static var databaseURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dahlia")
            .appendingPathComponent("dahlia.sqlite")
    }

    private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        // リリース前のため、旧スキーマとの互換性は持たず現行スキーマへ作り直す。
        migrator.eraseDatabaseOnSchemaChange = true

        migrator.registerMigration("v2_actionItemsSchema") { db in
            try createSchema(in: db)
        }

        return migrator
    }()

    private static func createSchema(in db: Database) throws {
        try createVaultsTable(in: db)
        try createProjectsTable(in: db)
        try createMeetingsTable(in: db)
        try createTranscriptSegmentsTable(in: db)
        try createTagsTable(in: db)
        try createMeetingTagsTable(in: db)
        try createNotesTable(in: db)
        try createScreenshotsTable(in: db)
        try createSummariesTable(in: db)
        try createActionItemsTable(in: db)
    }

    private static func createVaultsTable(in db: Database) throws {
        try db.create(table: "vaults") { t in
            t.primaryKey("id", .blob)
            t.column("path", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("lastOpenedAt", .datetime).notNull()
        }
    }

    private static func createProjectsTable(in db: Database) throws {
        try db.create(table: "projects") { t in
            t.primaryKey("id", .blob)
            t.column("vaultId", .blob).notNull()
                .references("vaults", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("missingOnDisk", .boolean).notNull().defaults(to: false)
            t.uniqueKey(["vaultId", "name"])
        }
        try db.create(
            index: "projects_on_vaultId",
            on: "projects",
            columns: ["vaultId"]
        )
    }

    private static func createMeetingsTable(in db: Database) throws {
        try db.create(table: "meetings") { t in
            t.primaryKey("id", .blob)
            t.column("vaultId", .blob).notNull()
                .references("vaults", onDelete: .cascade)
            t.column("projectId", .blob)
                .references("projects", onDelete: .setNull)
            t.column("name", .text).notNull().defaults(to: "")
            t.column("status", .text).notNull().defaults(to: MeetingStatus.transcriptNotFound.rawValue)
            t.column("duration", .double)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }
        try db.create(
            index: "meetings_on_projectId",
            on: "meetings",
            columns: ["projectId"]
        )
        try db.create(
            index: "meetings_on_projectId_createdAt",
            on: "meetings",
            columns: ["projectId", "createdAt"]
        )
        try db.create(
            index: "meetings_on_vaultId_createdAt",
            on: "meetings",
            columns: ["vaultId", "createdAt"]
        )
    }

    private static func createTranscriptSegmentsTable(in db: Database) throws {
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
    }

    private static func createTagsTable(in db: Database) throws {
        try db.create(table: "tags") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull().unique()
            t.column("colorHex", .text).notNull().defaults(to: "#808080")
            t.column("createdAt", .datetime).notNull()
        }
    }

    private static func createMeetingTagsTable(in db: Database) throws {
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

    private static func createNotesTable(in db: Database) throws {
        try db.create(table: "notes") { t in
            t.primaryKey("meetingId", .blob)
                .references("meetings", onDelete: .cascade)
            t.column("text", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }
    }

    private static func createScreenshotsTable(in db: Database) throws {
        try db.create(table: "screenshots") { t in
            t.primaryKey("id", .blob)
            t.column("meetingId", .blob).notNull()
                .references("meetings", onDelete: .cascade)
            t.column("capturedAt", .datetime).notNull()
            t.column("imageData", .blob).notNull()
            t.column("mimeType", .text).notNull()
        }
        try db.create(
            index: "screenshots_on_meetingId",
            on: "screenshots",
            columns: ["meetingId"]
        )
    }

    private static func createSummariesTable(in db: Database) throws {
        try db.create(table: "summaries") { t in
            t.primaryKey("meetingId", .blob)
                .references("meetings", onDelete: .cascade)
            t.column("title", .text).notNull().defaults(to: "")
            t.column("summary", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }
    }

    private static func createActionItemsTable(in db: Database) throws {
        try db.create(table: "action_items") { t in
            t.primaryKey("id", .blob)
            t.column("meetingId", .blob).notNull()
                .references("meetings", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("assignee", .text).notNull().defaults(to: "")
            t.column("isCompleted", .boolean).notNull().defaults(to: false)
        }
        try db.create(
            index: "action_items_on_meetingId",
            on: "action_items",
            columns: ["meetingId"]
        )
    }
}
