import Foundation

/// 検出されたビデオ会議の情報。
struct DetectedMeeting: Identifiable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String
}
