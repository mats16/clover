import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

struct GoogleCalendarConfigurationTests {
    @Test
    func clientIDIsReadFromEnvironment() {
        withTemporaryEnvironmentValue("GOOGLE_CLIENT_ID", value: "client-id-from-env") {
            #expect(GoogleCalendarConfiguration.clientID == "client-id-from-env")
        }
    }

    @Test
    func clientSecretIsReadFromEnvironment() {
        withTemporaryEnvironmentValue("GOOGLE_CLIENT_SECRET", value: "secret-from-env") {
            #expect(GoogleCalendarConfiguration.clientSecret == "secret-from-env")
        }
    }

    @Test
    func tokenRequestBodyIncludesClientSecretWhenConfigured() {
        let body = GoogleCalendarSignInAdapter.makeTokenRequestBody(
            clientID: "client-id",
            clientSecret: "client-secret",
            parameters: ["grant_type": "refresh_token"]
        )

        #expect(body["client_id"] == "client-id")
        #expect(body["client_secret"] == "client-secret")
        #expect(body["grant_type"] == "refresh_token")
    }
}
#elseif canImport(XCTest)
import XCTest

final class GoogleCalendarConfigurationTests: XCTestCase {
    func testClientIDIsReadFromEnvironment() {
        withTemporaryEnvironmentValue("GOOGLE_CLIENT_ID", value: "client-id-from-env") {
            XCTAssertEqual(GoogleCalendarConfiguration.clientID, "client-id-from-env")
        }
    }

    func testClientSecretIsReadFromEnvironment() {
        withTemporaryEnvironmentValue("GOOGLE_CLIENT_SECRET", value: "secret-from-env") {
            XCTAssertEqual(GoogleCalendarConfiguration.clientSecret, "secret-from-env")
        }
    }

    func testTokenRequestBodyIncludesClientSecretWhenConfigured() {
        let body = GoogleCalendarSignInAdapter.makeTokenRequestBody(
            clientID: "client-id",
            clientSecret: "client-secret",
            parameters: ["grant_type": "refresh_token"]
        )

        XCTAssertEqual(body["client_id"], "client-id")
        XCTAssertEqual(body["client_secret"], "client-secret")
        XCTAssertEqual(body["grant_type"], "refresh_token")
    }
}
#endif

private func withTemporaryEnvironmentValue(_ key: String, value: String, operation: () -> Void) {
    let original = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)
    defer {
        if let original {
            setenv(key, original, 1)
        } else {
            unsetenv(key)
        }
    }
    operation()
}
