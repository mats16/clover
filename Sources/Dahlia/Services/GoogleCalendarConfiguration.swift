import Foundation

enum GoogleCalendarConfiguration {
    private static let infoPlistClientIDKey = "GIDClientID"
    private static let infoPlistClientSecretKey = "GOOGLE_CLIENT_SECRET"
    private static let environmentClientIDKey = "GOOGLE_CLIENT_ID"
    private static let environmentClientSecretKey = "GOOGLE_CLIENT_SECRET"

    static var clientID: String? {
        nonEmptyValue(
            infoDictionaryValue(forKey: infoPlistClientIDKey) ??
                ProcessInfo.processInfo.environment[environmentClientIDKey]
        )
    }

    static var clientSecret: String? {
        nonEmptyValue(
            infoDictionaryValue(forKey: infoPlistClientSecretKey) ??
                ProcessInfo.processInfo.environment[environmentClientSecretKey]
        )
    }

    static var isConfigured: Bool {
        clientID != nil
    }

    private static func infoDictionaryValue(forKey key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func nonEmptyValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
