import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
import Testing

struct AppDatabaseManagerTests {
    @Test
    func initializesInMemoryDatabaseWithCalendarEventsTable() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let tableNames = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        #expect(tableNames.contains("vaults"))
        #expect(tableNames.contains("calendar_events"))
    }
}
#elseif canImport(XCTest)
import XCTest

final class AppDatabaseManagerTests: XCTestCase {
    func testInitializesInMemoryDatabaseWithCalendarEventsTable() throws {
        let database = try AppDatabaseManager(path: ":memory:")

        let tableNames = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        XCTAssertTrue(tableNames.contains("vaults"))
        XCTAssertTrue(tableNames.contains("calendar_events"))
    }
}
#endif
