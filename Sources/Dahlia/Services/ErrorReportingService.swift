import Foundation
@preconcurrency import Sentry

/// Sentry を用いたエラー報告サービス。
/// 環境変数 `SENTRY_DSN` が設定されている場合のみ有効化される。
enum ErrorReportingService {
    private nonisolated(unsafe) static var isEnabled = false

    /// アプリ起動時に一度だけ呼ぶ。`SENTRY_DSN` 環境変数が未設定なら何もしない。
    static func start() {
        guard let dsn = ProcessInfo.processInfo.environment["SENTRY_DSN"],
              !dsn.isEmpty
        else { return }

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
}
