import Foundation

/// ローカライズ文字列への型安全なアクセスを提供する。
enum L10n {
    private static let bundle: Bundle = .module

    // MARK: - Common

    static var delete: String { String(localized: "Delete", bundle: bundle) }
    static var rename: String { String(localized: "Rename", bundle: bundle) }
    static var create: String { String(localized: "Create", bundle: bundle) }

    // MARK: - Sidebar

    static var newProject: String { String(localized: "New Project", bundle: bundle) }
    static var projectName: String { String(localized: "Project Name", bundle: bundle) }
    static var editReadme: String { String(localized: "Edit README", bundle: bundle) }
    static var title: String { String(localized: "Title", bundle: bundle) }

    // MARK: - Control Panel

    static var preparingSpeechRecognition: String { String(localized: "Preparing speech recognition...", bundle: bundle) }
    static var recognizing: String { String(localized: "Recognizing...", bundle: bundle) }
    static var transcription: String { String(localized: "Transcription", bundle: bundle) }
    static func segmentCount(_ count: Int) -> String { String(localized: "\(count) segments", bundle: bundle) }
    static var stop: String { String(localized: "Stop", bundle: bundle) }
    static var resume: String { String(localized: "Resume", bundle: bundle) }
    static var record: String { String(localized: "Record", bundle: bundle) }
    static var export: String { String(localized: "Export", bundle: bundle) }
    static var clearTranscription: String { String(localized: "Clear transcription", bundle: bundle) }

    // MARK: - Audio Source Mode

    static var mic: String { String(localized: "Mic", bundle: bundle) }
    static var system: String { String(localized: "System", bundle: bundle) }
    static var both: String { String(localized: "Both", bundle: bundle) }

    // MARK: - Settings

    static var vault: String { String(localized: "Vault", bundle: bundle) }
    static var change: String { String(localized: "Change...", bundle: bundle) }
    static var vaultDescription: String { String(localized: "Root directory where project folders are stored.", bundle: bundle) }
    static var loadingLanguages: String { String(localized: "Loading supported languages...", bundle: bundle) }
    static var searchLanguages: String { String(localized: "Search languages...", bundle: bundle) }
    static var noMatchingLanguages: String { String(localized: "No matching languages", bundle: bundle) }
    static var allLanguagesShown: String { String(localized: "All languages shown", bundle: bundle) }
    static func languagesSelected(_ count: Int) -> String { String(localized: "\(count) languages selected", bundle: bundle) }
    static var showAll: String { String(localized: "Show all", bundle: bundle) }
    static var displayLanguages: String { String(localized: "Display Languages", bundle: bundle) }
    static var displayLanguagesDescription: String { String(localized: "Only selected languages will appear in the language picker. All languages are shown if none are selected.", bundle: bundle) }

    // MARK: - Error Messages (Audio)

    static var screenRecordingDenied: String { String(localized: "Screen recording access denied. Please allow it in System Settings > Privacy & Security > Screen Recording.", bundle: bundle) }
    static var noDisplayFound: String { String(localized: "No available displays found", bundle: bundle) }
    static var invalidHardwareFormat: String { String(localized: "Invalid audio hardware format", bundle: bundle) }
    static var converterCreationFailed: String { String(localized: "Failed to create audio format converter", bundle: bundle) }
    static var microphoneDenied: String { String(localized: "Microphone access denied. Please allow it in System Settings > Privacy & Security > Microphone.", bundle: bundle) }

    // MARK: - Error Messages (ViewModel)

    static var speechRecognitionUnavailable: String { String(localized: "Speech recognition is not available on this Mac", bundle: bundle) }
    static func speechPreparationFailed(_ error: String) -> String { String(localized: "Failed to prepare speech recognition: \(error)", bundle: bundle) }
    static func languageChangeFailed(_ error: String) -> String { String(localized: "Failed to change language: \(error)", bundle: bundle) }
    static var speechRecognitionNotReady: String { String(localized: "Speech recognition is not ready", bundle: bundle) }
    static var systemAudioCaptureStopped: String { String(localized: "System audio capture stopped", bundle: bundle) }
}
