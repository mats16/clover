import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

struct GoogleCalendarAPIClientTests {
    @Test
    func calendarListDecodingAllowsMissingOptionalFields() throws {
        let data = Data("""
        {
          "items": [
            {
              "id": "primary"
            }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(GoogleCalendarAPIClient.CalendarListResponse.self, from: data)

        #expect(response.items.count == 1)
        #expect(response.items[0].id == "primary")
        #expect(response.items[0].summary == nil)
        #expect(response.items[0].primary == false)
        #expect(response.items[0].deleted == false)
    }

    @Test
    func calendarListDecodingAllowsMissingItemsArray() throws {
        let data = Data("{}".utf8)

        let response = try JSONDecoder().decode(GoogleCalendarAPIClient.CalendarListResponse.self, from: data)

        #expect(response.items.isEmpty)
    }
}
#elseif canImport(XCTest)
import XCTest

final class GoogleCalendarAPIClientTests: XCTestCase {
    func testCalendarListDecodingAllowsMissingOptionalFields() throws {
        let data = Data("""
        {
          "items": [
            {
              "id": "primary"
            }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(GoogleCalendarAPIClient.CalendarListResponse.self, from: data)

        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items[0].id, "primary")
        XCTAssertNil(response.items[0].summary)
        XCTAssertFalse(response.items[0].primary)
        XCTAssertFalse(response.items[0].deleted)
    }

    func testCalendarListDecodingAllowsMissingItemsArray() throws {
        let data = Data("{}".utf8)

        let response = try JSONDecoder().decode(GoogleCalendarAPIClient.CalendarListResponse.self, from: data)

        XCTAssertTrue(response.items.isEmpty)
    }
}
#endif
