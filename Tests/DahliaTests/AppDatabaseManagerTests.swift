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
}
#endif
