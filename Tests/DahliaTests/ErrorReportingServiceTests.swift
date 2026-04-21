import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

struct ErrorReportingServiceTests {
    @Test
    func resolveDSNUsesPlistValueForReleaseBuild() {
        let dsn = ErrorReportingService.resolveDSN(
            infoDictionary: ["SENTRY_DSN": "https://examplePublicKey@o0.ingest.sentry.io/1"],
            isDebugBuild: false
        )

        #expect(dsn == "https://examplePublicKey@o0.ingest.sentry.io/1")
    }

    @Test
    func resolveDSNIgnoresWhitespaceOnlyValues() {
        let dsn = ErrorReportingService.resolveDSN(
            infoDictionary: ["SENTRY_DSN": "   \n  "],
            isDebugBuild: false
        )

        #expect(dsn == nil)
    }

    @Test
    func resolveDSNDisablesSentryForDebugBuilds() {
        let dsn = ErrorReportingService.resolveDSN(
            infoDictionary: ["SENTRY_DSN": "https://examplePublicKey@o0.ingest.sentry.io/1"],
            isDebugBuild: true
        )

        #expect(dsn == nil)
    }
}
#endif
