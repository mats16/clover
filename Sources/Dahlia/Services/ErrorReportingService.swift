import Foundation
@preconcurrency import Sentry

/// Sentry を用いたエラー報告サービス。
enum ErrorReportingService {
    private static let dsnInfoKey = "SENTRY_DSN"
    private nonisolated(unsafe) static var isEnabled = false

    static func start() {
        guard let dsn = configuredDSN else { return }

        isEnabled = true
        SentrySDK.start { options in
            options.dsn = dsn
            options.enableCrashHandler = true
            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0
            options.sendDefaultPii = false
            #if DEBUG
                options.environment = "debug"
            #else
                options.environment = "production"
            #endif
        }
    }

    static func capture(_ error: Error, context: [String: String] = [:]) {
        guard isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setExtra(value: value, key: key)
            }
        }
    }

    static func resolveDSN(infoDictionary: [String: Any], isDebugBuild: Bool) -> String? {
        guard !isDebugBuild else { return nil }
        guard let rawDSN = infoDictionary[dsnInfoKey] as? String else { return nil }

        let dsn = rawDSN.trimmingCharacters(in: .whitespacesAndNewlines)
        return dsn.isEmpty ? nil : dsn
    }

    private static var configuredDSN: String? {
        resolveDSN(infoDictionary: Bundle.main.infoDictionary ?? [:], isDebugBuild: isDebugBuild)
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }
}
