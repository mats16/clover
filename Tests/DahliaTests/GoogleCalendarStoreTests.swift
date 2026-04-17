import AppKit
import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

@MainActor
struct GoogleCalendarStoreTests {
    @Test
    func unconfiguredStoreStartsInUnconfiguredState() {
        let store = GoogleCalendarStore(
            signInProvider: MockGoogleCalendarSignInProvider(isConfigured: false),
            apiClient: MockGoogleCalendarAPIClient(),
            userDefaults: isolatedUserDefaults()
        )

        #expect(store.state == .unconfigured)
        #expect(!store.isConfigured)
    }

    @Test
    func restorePreviousSessionLoadsCalendarsAndEvents() async throws {
        let defaults = isolatedUserDefaults()
        seedSelectedCalendars(["primary"], defaults: defaults)

        let signInProvider = MockGoogleCalendarSignInProvider(
            hasPreviousSignIn: true,
            restoreResult: .success(fixtureSession)
        )
        let apiClient = MockGoogleCalendarAPIClient(
            calendars: [primaryCalendar],
            events: [fixtureEvent]
        )
        let store = GoogleCalendarStore(
            signInProvider: signInProvider,
            apiClient: apiClient,
            userDefaults: defaults,
            now: { fixtureNow }
        )

        await store.restoreSessionIfNeeded()

        #expect(store.state == .loaded)
        #expect(store.account == fixtureSession.account)
        #expect(store.availableCalendars == [primaryCalendar])
        #expect(store.upcomingEvents == [fixtureEvent])
        #expect(apiClient.fetchEventsCallCount == 1)
    }

    @Test
    func restoreFailureMapsWebClientIDErrorToActionableMessage() async {
        let signInProvider = MockGoogleCalendarSignInProvider(
            hasPreviousSignIn: true,
            restoreResult: .failure(
                NSError(
                    domain: "GoogleSignIn",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "invalid_request: client_secret is missing."]
                )
            )
        )
        let store = GoogleCalendarStore(
            signInProvider: signInProvider,
            apiClient: MockGoogleCalendarAPIClient(),
            userDefaults: isolatedUserDefaults()
        )

        await store.restoreSessionIfNeeded()

        #expect(store.state == .failed)
        #expect(store.lastErrorMessage == L10n.googleCalendarClientSecretMissingMessage)
        #expect(store.account == nil)
    }

    @Test
    func restoreWithoutSelectedCalendarsRequiresSelection() async {
        let signInProvider = MockGoogleCalendarSignInProvider(
            hasPreviousSignIn: true,
            restoreResult: .success(fixtureSession)
        )
        let apiClient = MockGoogleCalendarAPIClient(calendars: [primaryCalendar], events: [])
        let store = GoogleCalendarStore(
            signInProvider: signInProvider,
            apiClient: apiClient,
            userDefaults: isolatedUserDefaults(),
            now: { fixtureNow }
        )

        await store.restoreSessionIfNeeded()

        #expect(store.state == .needsCalendarSelection)
        #expect(store.upcomingEvents.isEmpty)
    }

    @Test
    func disconnectClearsSelectionAndCachedData() async {
        let defaults = isolatedUserDefaults()
        seedSelectedCalendars(["primary"], defaults: defaults)

        let signInProvider = MockGoogleCalendarSignInProvider(
            hasPreviousSignIn: true,
            restoreResult: .success(fixtureSession)
        )
        let apiClient = MockGoogleCalendarAPIClient(
            calendars: [primaryCalendar],
            events: [fixtureEvent]
        )
        let store = GoogleCalendarStore(
            signInProvider: signInProvider,
            apiClient: apiClient,
            userDefaults: defaults,
            now: { fixtureNow }
        )

        await store.restoreSessionIfNeeded()
        await store.disconnect()

        #expect(signInProvider.disconnectCallCount == 1)
        #expect(store.state == .signedOut)
        #expect(store.selectedCalendarIDs.isEmpty)
        #expect(store.account == nil)
        #expect(store.availableCalendars.isEmpty)
        #expect(store.upcomingEvents.isEmpty)
    }

    @Test
    func setCalendarSelectionPersistsIDs() async {
        let defaults = isolatedUserDefaults()
        let signInProvider = MockGoogleCalendarSignInProvider(
            hasPreviousSignIn: true,
            restoreResult: .success(fixtureSession),
            refreshResult: .success(fixtureSession)
        )
        let apiClient = MockGoogleCalendarAPIClient(
            calendars: [primaryCalendar, secondaryCalendar],
            events: [fixtureEvent]
        )
        let store = GoogleCalendarStore(
            signInProvider: signInProvider,
            apiClient: apiClient,
            userDefaults: defaults,
            now: { fixtureNow }
        )

        await store.restoreSessionIfNeeded()
        store.setCalendarSelection([secondaryCalendar.id])

        #expect(store.selectedCalendarIDs == [secondaryCalendar.id])

        let saved = defaults.string(forKey: GoogleCalendarStore.selectedCalendarIDsKey)
        #expect(saved?.contains(secondaryCalendar.id) == true)
    }

    @Test
    func eventTransformationPrefersConferenceEntryPointAndFiltersFutureWindow() throws {
        let conferenceItem = GoogleCalendarAPIClient.EventItem(
            id: "event-1",
            summary: "Weekly sync",
            hangoutLink: nil,
            start: .init(date: nil, dateTime: "2026-04-17T01:00:00Z"),
            end: .init(date: nil, dateTime: "2026-04-17T02:00:00Z"),
            conferenceData: .init(entryPoints: [.init(uri: "https://meet.google.com/abc-defg-hij")])
        )
        let event = try #require(
            GoogleCalendarAPIClient.makeEvent(
                from: conferenceItem,
                calendarItem: primaryCalendar,
                calendar: .current
            )
        )

        #expect(event.meetingURL?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(!event.isAllDay)

        let intervalEnd = Calendar.current.date(byAdding: .day, value: 7, to: fixtureNow)!
        let filtered = GoogleCalendarAPIClient.sortAndFilter(
            [
                event,
                GoogleCalendarEvent(
                    id: "late",
                    calendarID: primaryCalendar.id,
                    calendarName: primaryCalendar.title,
                    calendarColorHex: nil,
                    title: "Outside window",
                    startDate: Calendar.current.date(byAdding: .day, value: 9, to: fixtureNow)!,
                    endDate: Calendar.current.date(byAdding: .day, value: 9, to: fixtureNow)!,
                    isAllDay: true,
                    meetingURL: nil
                ),
            ],
            now: fixtureNow,
            intervalEnd: intervalEnd
        )

        #expect(filtered == [event])
    }

    @Test
    func allDayEventUsesDateField() throws {
        let allDayItem = GoogleCalendarAPIClient.EventItem(
            id: "event-2",
            summary: nil,
            hangoutLink: nil,
            start: .init(date: "2026-04-18", dateTime: nil),
            end: .init(date: "2026-04-19", dateTime: nil),
            conferenceData: nil
        )

        let event = try #require(
            GoogleCalendarAPIClient.makeEvent(
                from: allDayItem,
                calendarItem: secondaryCalendar,
                calendar: Calendar(identifier: .gregorian)
            )
        )

        #expect(event.isAllDay)
        #expect(event.title == L10n.googleCalendarUntitledEvent)
    }
}
#elseif canImport(XCTest)
import XCTest

@MainActor
final class GoogleCalendarStoreTests: XCTestCase {
    func testUnconfiguredStoreStartsInUnconfiguredState() {
        let store = GoogleCalendarStore(
            signInProvider: MockGoogleCalendarSignInProvider(isConfigured: false),
            apiClient: MockGoogleCalendarAPIClient(),
            userDefaults: isolatedUserDefaults()
        )

        XCTAssertEqual(store.state, .unconfigured)
        XCTAssertFalse(store.isConfigured)
    }

    func testRestorePreviousSessionLoadsCalendarsAndEvents() async throws {
        let defaults = isolatedUserDefaults()
        seedSelectedCalendars(["primary"], defaults: defaults)

        let signInProvider = MockGoogleCalendarSignInProvider(
            hasPreviousSignIn: true,
            restoreResult: .success(fixtureSession)
        )
        let apiClient = MockGoogleCalendarAPIClient(
            calendars: [primaryCalendar],
            events: [fixtureEvent]
        )
        let store = GoogleCalendarStore(
            signInProvider: signInProvider,
            apiClient: apiClient,
            userDefaults: defaults,
            now: { fixtureNow }
        )

        await store.restoreSessionIfNeeded()

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.account, fixtureSession.account)
        XCTAssertEqual(store.availableCalendars, [primaryCalendar])
        XCTAssertEqual(store.upcomingEvents, [fixtureEvent])
        XCTAssertEqual(apiClient.fetchEventsCallCount, 1)
    }

    func testRestoreFailureMapsWebClientIDErrorToActionableMessage() async {
        let signInProvider = MockGoogleCalendarSignInProvider(
            hasPreviousSignIn: true,
            restoreResult: .failure(
                NSError(
                    domain: "GoogleSignIn",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "invalid_request: client_secret is missing."]
                )
            )
        )
        let store = GoogleCalendarStore(
            signInProvider: signInProvider,
            apiClient: MockGoogleCalendarAPIClient(),
            userDefaults: isolatedUserDefaults()
        )

        await store.restoreSessionIfNeeded()

        XCTAssertEqual(store.state, .failed)
        XCTAssertEqual(store.lastErrorMessage, L10n.googleCalendarClientSecretMissingMessage)
        XCTAssertNil(store.account)
    }
}
#endif

private let fixtureNow = Date(timeIntervalSince1970: 1_776_384_000)

private let fixtureSession = GoogleCalendarSession(
    account: GoogleCalendarAccount(
        id: "user-1",
        displayName: "Kazuki Matsuda",
        email: "kazuki@example.com"
    ),
    accessToken: "token-1"
)

private let primaryCalendar = GoogleCalendarListItem(
    id: "primary",
    title: "Primary",
    colorHex: "#4285F4",
    isPrimary: true
)

private let secondaryCalendar = GoogleCalendarListItem(
    id: "team@example.com",
    title: "Team",
    colorHex: "#34A853",
    isPrimary: false
)

private let fixtureEvent = GoogleCalendarEvent(
    id: "primary::event-1",
    calendarID: "primary",
    calendarName: "Primary",
    calendarColorHex: "#4285F4",
    title: "Design review",
    startDate: fixtureNow.addingTimeInterval(3600),
    endDate: fixtureNow.addingTimeInterval(7200),
    isAllDay: false,
    meetingURL: URL(string: "https://meet.google.com/test-link")
)

@MainActor
private final class MockGoogleCalendarSignInProvider: GoogleCalendarSignInProviding {
    let isConfigured: Bool
    let hasPreviousSignIn: Bool
    var restoreResult: Result<GoogleCalendarSession, Error>
    var signInResult: Result<GoogleCalendarSession, Error>
    var refreshResult: Result<GoogleCalendarSession?, Error>
    private(set) var disconnectCallCount = 0

    init(
        isConfigured: Bool = true,
        hasPreviousSignIn: Bool = false,
        restoreResult: Result<GoogleCalendarSession, Error> = .success(fixtureSession),
        signInResult: Result<GoogleCalendarSession, Error> = .success(fixtureSession),
        refreshResult: Result<GoogleCalendarSession?, Error> = .success(fixtureSession)
    ) {
        self.isConfigured = isConfigured
        self.hasPreviousSignIn = hasPreviousSignIn
        self.restoreResult = restoreResult
        self.signInResult = signInResult
        self.refreshResult = refreshResult
    }

    func restorePreviousSignIn() async throws -> GoogleCalendarSession {
        try restoreResult.get()
    }

    func signIn(withPresentingWindow _: NSWindow) async throws -> GoogleCalendarSession {
        try signInResult.get()
    }

    func refreshCurrentSession() async throws -> GoogleCalendarSession? {
        try refreshResult.get()
    }

    func disconnect() async throws {
        disconnectCallCount += 1
    }
}

@MainActor
private final class MockGoogleCalendarAPIClient: GoogleCalendarAPIClientProviding {
    private let calendarsResult: Result<[GoogleCalendarListItem], Error>
    private let eventsResult: Result<[GoogleCalendarEvent], Error>
    private(set) var fetchEventsCallCount = 0

    init(
        calendars: [GoogleCalendarListItem] = [],
        events: [GoogleCalendarEvent] = []
    ) {
        calendarsResult = .success(calendars)
        eventsResult = .success(events)
    }

    func fetchCalendarList(accessToken _: String) async throws -> [GoogleCalendarListItem] {
        try calendarsResult.get()
    }

    func fetchUpcomingEvents(
        accessToken _: String,
        calendars _: [GoogleCalendarListItem],
        now _: Date,
        daysAhead _: Int
    ) async throws -> [GoogleCalendarEvent] {
        fetchEventsCallCount += 1
        return try eventsResult.get()
    }
}

private func isolatedUserDefaults() -> UserDefaults {
    let suiteName = "GoogleCalendarStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func seedSelectedCalendars(_ ids: [String], defaults: UserDefaults) {
    let data = try! JSONEncoder().encode(ids)
    defaults.set(String(data: data, encoding: .utf8), forKey: GoogleCalendarStore.selectedCalendarIDsKey)
}
