import Foundation
import GRDB

/// プロジェクトフォルダ単位で SQLite データベースを管理する。
/// 各プロジェクトフォルダ直下に `.transcriptions.sqlite` を作成・オープンする。
final class ProjectDatabaseManager: Sendable {
    let dbQueue: DatabaseQueue

    init(projectURL: URL) throws {
        let dbPath = projectURL.appendingPathComponent(".transcriptions.sqlite")
        dbQueue = try DatabaseQueue(path: dbPath.path)
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_folderSchema") { db in
            // transcriptions テーブル（projectId なし — DB 自体がプロジェクトスコープ）
            try db.create(table: "transcriptions") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("locale", .text).notNull()
                t.column("audioSourceMode", .text).notNull()
            }

            // segments テーブル
            try db.create(table: "segments") { t in
                t.primaryKey("id", .blob)
                t.column("transcriptionId", .blob).notNull()
                    .references("transcriptions", onDelete: .cascade)
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

        migrator.registerMigration("v2_renameTables") { db in
            // 既存 DB のテーブル名を複数形にリネーム
            if try db.tableExists("transcription") {
                try db.rename(table: "transcription", to: "transcriptions")
            }
            if try db.tableExists("segment") {
                try db.rename(table: "segment", to: "segments")
            }

            // speakerLabel の値を英語に変更
            try db.execute(sql: """
                UPDATE segments SET speakerLabel = 'mic' WHERE speakerLabel = 'マイク'
                """)
            try db.execute(sql: """
                UPDATE segments SET speakerLabel = 'system' WHERE speakerLabel = 'システム'
                """)
        }

        migrator.registerMigration("v3_dropLocaleAndAudioSourceMode") { db in
            try db.alter(table: "transcriptions") { t in
                t.drop(column: "locale")
                t.drop(column: "audioSourceMode")
            }
        }

        return migrator
    }
}
