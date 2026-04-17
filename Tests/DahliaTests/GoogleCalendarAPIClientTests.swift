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

    @Test
    func fetchUpcomingEventsRequestsOnlySupportedEventTypes() async throws {
        let requestRecorder = RequestRecorderURLProtocol()
        let session = makeRecordingSession(recorder: requestRecorder)
        let client = GoogleCalendarAPIClient(session: session, calendar: Calendar(identifier: .gregorian))

        _ = try await client.fetchUpcomingEvents(
            accessToken: "token",
            calendars: [
                GoogleCalendarListItem(
                    id: "primary",
                    title: "Primary",
                    colorHex: nil,
                    isPrimary: true
                ),
            ],
            now: Date(timeIntervalSince1970: 1_776_384_000),
            daysAhead: 7
        )

        let request = try #require(requestRecorder.lastRequest)
        let queryItems = try #require(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        let eventTypes = queryItems
            .filter { $0.name == "eventTypes" }
            .compactMap(\.value)

        #expect(Set(eventTypes) == Set(["default", "focusTime", "fromGmail"]))
        #expect(!eventTypes.contains("outOfOffice"))
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

    func testFetchUpcomingEventsRequestsOnlySupportedEventTypes() async throws {
        let requestRecorder = RequestRecorderURLProtocol()
        let session = makeRecordingSession(recorder: requestRecorder)
        let client = GoogleCalendarAPIClient(session: session, calendar: Calendar(identifier: .gregorian))

        _ = try await client.fetchUpcomingEvents(
            accessToken: "token",
            calendars: [
                GoogleCalendarListItem(
                    id: "primary",
                    title: "Primary",
                    colorHex: nil,
                    isPrimary: true
                ),
            ],
            now: Date(timeIntervalSince1970: 1_776_384_000),
            daysAhead: 7
        )

        let request = try XCTUnwrap(requestRecorder.lastRequest)
        let url = try XCTUnwrap(request.url)
        let queryItems = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let eventTypes = queryItems
            .filter { $0.name == "eventTypes" }
            .compactMap(\.value)

        XCTAssertEqual(Set(eventTypes), Set(["default", "focusTime", "fromGmail"]))
        XCTAssertFalse(eventTypes.contains("outOfOffice"))
    }
}
#endif

private final class RequestRecorderURLProtocol: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var lastRequest: URLRequest? {
        lock.withLock { storedRequest }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            storedRequest = request
        }
    }
}

private func makeRecordingSession(recorder: RequestRecorderURLProtocol) -> URLSession {
    RecordingURLProtocol.recorder = recorder

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var recorder: RequestRecorderURLProtocol?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.recorder?.record(request)

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data(#"{"items":[]}"#.utf8)

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
