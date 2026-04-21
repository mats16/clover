import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
import Testing

struct AppDatabaseManagerTests {
    @Test
    func initializesInMemoryDatabaseWithGoogleDriveFolderColumn() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "PRAGMA table_info(projects)")
        }

        #expect(columns.contains("googleDriveFolderId"))
    }

    @Test
    func initializesInMemoryDatabaseWithSummaryGoogleFileIdColumn() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('summaries')")
        }

        #expect(columns.contains("googleFileId"))
    }

    @Test
    func initializesInMemoryDatabaseWithTranscriptTranslatedTextColumn() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('transcript_segments')")
        }

        #expect(columns.contains("translatedText"))
    }

    @Test
    func repositoryUpdatesProjectGoogleDriveFolder() throws {
        let database = try AppDatabaseManager(path: ":memory:")
        let repository = MeetingRepository(dbQueue: database.dbQueue)
        let vault = VaultRecord(
            id: .v7(),
            path: "/tmp/test-vault",
            name: "Test Vault",
            createdAt: Date(),
            lastOpenedAt: Date()
        )
        try repository.insertVault(vault)

        let project = try repository.fetchOrCreateProject(name: "Project A", vaultId: vault.id)
        try repository.updateProjectGoogleDriveFolder(id: project.id, folderId: "folder-123")

        let updatedProject = try #require(repository.fetchProject(id: project.id))
        #expect(updatedProject.googleDriveFolderId == "folder-123")
    }

    @Test
    func initializesInstructionsTableWithConstraints() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columnNames = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('instructions')")
        }
        let hasCompositeUniqueIndex = try database.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM (
                    SELECT il.name
                    FROM pragma_index_list('instructions') AS il
                    JOIN pragma_index_info(il.name) AS ii
                    WHERE il."unique" = 1
                    GROUP BY il.name
                    HAVING group_concat(ii.name, ',') = 'vaultId,name'
                )
                """
            )
        }

        #expect(columnNames.contains("vaultId"))
        #expect(columnNames.contains("name"))
        #expect(columnNames.contains("content"))
        #expect(hasCompositeUniqueIndex == 1)
    }

    @Test
    func existingV3DatabaseMigratesInstructionsTable() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.create(table: "vaults") { t in
                t.primaryKey("id", .blob)
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime).notNull()
            }
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v3_googleDriveFolderSchema"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let tables = try migrated.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        #expect(tables.contains("instructions"))
    }

    @Test
    func existingV3DatabasePreservesExistingDataDuringMigration() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let legacyVaultID = UUID.v7()
        let createdAt = Date.now

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.create(table: "vaults") { t in
                t.primaryKey("id", .blob)
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime).notNull()
            }
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO vaults (id, path, name, createdAt, lastOpenedAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [legacyVaultID, "/tmp/legacy-vault", "Legacy Vault", createdAt, createdAt]
            )
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v3_googleDriveFolderSchema"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let migratedVault = try migrated.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT id, path, name FROM vaults WHERE id = ?",
                arguments: [legacyVaultID]
            )
        }

        #expect(migratedVault != nil)
        #expect(migratedVault?["path"] == "/tmp/legacy-vault")
        #expect(migratedVault?["name"] == "Legacy Vault")
    }

    @Test
    func existingV4DatabaseMigratesSummaryGoogleFileIdColumn() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.create(table: "summaries") { t in
                t.primaryKey("meetingId", .blob)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("summary", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v4_instructionsSchema"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let columns = try migrated.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('summaries')")
        }

        #expect(columns.contains("googleFileId"))
    }

    @Test
    func existingV5DatabaseMigratesTranscriptTranslatedTextColumnWithoutDataLoss() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let segmentID = UUID.v7()
        let meetingID = UUID.v7()
        let startTime = Date(timeIntervalSince1970: 1_776_384_000)

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.execute(
                sql: """
                CREATE TABLE transcript_segments (
                    id BLOB PRIMARY KEY,
                    meetingId BLOB NOT NULL,
                    startTime DATETIME NOT NULL,
                    endTime DATETIME,
                    text TEXT NOT NULL,
                    isConfirmed BOOLEAN NOT NULL DEFAULT 0,
                    speakerLabel TEXT
                )
                """
            )
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO transcript_segments (id, meetingId, startTime, text, isConfirmed, speakerLabel)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [segmentID, meetingID, startTime, "Hello world", true, "mic"]
            )
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v5_summaryGoogleFileId"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let result = try migrated.dbQueue.read { db in
            (
                try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('transcript_segments')"),
                try Row.fetchOne(db, sql: "SELECT text, translatedText FROM transcript_segments WHERE id = ?", arguments: [segmentID])
            )
        }

        #expect(result.0.contains("translatedText"))
        #expect(result.1?["text"] == "Hello world")
        #expect(result.1?["translatedText"] == nil as String?)
    }
}
#elseif canImport(XCTest)
import XCTest

final class AppDatabaseManagerTests: XCTestCase {
    func testInitializesInMemoryDatabaseWithGoogleDriveFolderColumn() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "PRAGMA table_info(projects)")
        }

        XCTAssertTrue(columns.contains("googleDriveFolderId"))
    }

    func testInitializesInMemoryDatabaseWithSummaryGoogleFileIdColumn() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('summaries')")
        }

        XCTAssertTrue(columns.contains("googleFileId"))
    }

    func testInitializesInMemoryDatabaseWithTranscriptTranslatedTextColumn() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('transcript_segments')")
        }

        XCTAssertTrue(columns.contains("translatedText"))
    }

    func testRepositoryUpdatesProjectGoogleDriveFolder() throws {
        let database = try AppDatabaseManager(path: ":memory:")
        let repository = MeetingRepository(dbQueue: database.dbQueue)
        let vault = VaultRecord(
            id: .v7(),
            path: "/tmp/test-vault",
            name: "Test Vault",
            createdAt: Date(),
            lastOpenedAt: Date()
        )
        try repository.insertVault(vault)

        let project = try repository.fetchOrCreateProject(name: "Project A", vaultId: vault.id)
        try repository.updateProjectGoogleDriveFolder(id: project.id, folderId: "folder-123")

        let updatedProject = try XCTUnwrap(repository.fetchProject(id: project.id))
        XCTAssertEqual(updatedProject.googleDriveFolderId, "folder-123")
    }

    func testInitializesInstructionsTableWithConstraints() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let columnNames = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('instructions')")
        }
        let hasCompositeUniqueIndex = try database.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM (
                    SELECT il.name
                    FROM pragma_index_list('instructions') AS il
                    JOIN pragma_index_info(il.name) AS ii
                    WHERE il."unique" = 1
                    GROUP BY il.name
                    HAVING group_concat(ii.name, ',') = 'vaultId,name'
                )
                """
            )
        }

        XCTAssertTrue(columnNames.contains("vaultId"))
        XCTAssertTrue(columnNames.contains("name"))
        XCTAssertTrue(columnNames.contains("content"))
        XCTAssertEqual(hasCompositeUniqueIndex, 1)
    }

    func testExistingV3DatabaseMigratesInstructionsTable() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.create(table: "vaults") { t in
                t.primaryKey("id", .blob)
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime).notNull()
            }
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v3_googleDriveFolderSchema"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let tables = try migrated.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        XCTAssertTrue(tables.contains("instructions"))
    }

    func testExistingV3DatabasePreservesExistingDataDuringMigration() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let legacyVaultID = UUID.v7()
        let createdAt = Date.now

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.create(table: "vaults") { t in
                t.primaryKey("id", .blob)
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime).notNull()
            }
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO vaults (id, path, name, createdAt, lastOpenedAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [legacyVaultID, "/tmp/legacy-vault", "Legacy Vault", createdAt, createdAt]
            )
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v3_googleDriveFolderSchema"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let migratedVault = try migrated.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT id, path, name FROM vaults WHERE id = ?",
                arguments: [legacyVaultID]
            )
        }

        XCTAssertNotNil(migratedVault)
        XCTAssertEqual(migratedVault?["path"], "/tmp/legacy-vault")
        XCTAssertEqual(migratedVault?["name"], "Legacy Vault")
    }

    func testExistingV4DatabaseMigratesSummaryGoogleFileIdColumn() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.create(table: "summaries") { t in
                t.primaryKey("meetingId", .blob)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("summary", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v4_instructionsSchema"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let columns = try migrated.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('summaries')")
        }

        XCTAssertTrue(columns.contains("googleFileId"))
    }

    func testExistingV5DatabaseMigratesTranscriptTranslatedTextColumnWithoutDataLoss() throws {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let segmentID = UUID.v7()
        let meetingID = UUID.v7()
        let startTime = Date(timeIntervalSince1970: 1_776_384_000)

        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.execute(
                sql: """
                CREATE TABLE transcript_segments (
                    id BLOB PRIMARY KEY,
                    meetingId BLOB NOT NULL,
                    startTime DATETIME NOT NULL,
                    endTime DATETIME,
                    text TEXT NOT NULL,
                    isConfirmed BOOLEAN NOT NULL DEFAULT 0,
                    speakerLabel TEXT
                )
                """
            )
            try db.create(table: "grdb_migrations") { t in
                t.column("identifier", .text).primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO transcript_segments (id, meetingId, startTime, text, isConfirmed, speakerLabel)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [segmentID, meetingID, startTime, "Hello world", true, "mic"]
            )
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v5_summaryGoogleFileId"]
            )
        }

        let migrated = try AppDatabaseManager(path: databaseURL.path)
        let result = try migrated.dbQueue.read { db in
            (
                try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('transcript_segments')"),
                try Row.fetchOne(db, sql: "SELECT text, translatedText FROM transcript_segments WHERE id = ?", arguments: [segmentID])
            )
        }

        XCTAssertTrue(result.0.contains("translatedText"))
        XCTAssertEqual(result.1?["text"], "Hello world")
        XCTAssertNil(result.1?["translatedText"] as String?)
    }
}
#endif
