import Foundation

/// ローカライズ文字列への型安全なアクセスを提供する。
enum L10n {
    /// キャッシュ済みの Bundle と、その生成元の言語 rawValue。
    /// 言語設定が変わらない限り Bundle を再生成しない。
    nonisolated(unsafe) private static var cachedBundle: Bundle = .module
    nonisolated(unsafe) private static var cachedLanguageRaw: String = ""

    /// 選択された表示言語に対応する Bundle を返す。
    /// UserDefaults から直接読み取ることで @MainActor 制約を回避する。
    nonisolated private static var bundle: Bundle {
        let rawValue = UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey) ?? AppLanguage.system.rawValue
        if rawValue == cachedLanguageRaw { return cachedBundle }
        let resolved: Bundle
        if let language = AppLanguage(rawValue: rawValue),
           let lprojName = language.lprojName,
           let path = Bundle.module.path(forResource: lprojName, ofType: "lproj"),
           let lprojBundle = Bundle(path: path) {
            resolved = lprojBundle
        } else {
            resolved = .module
        }
        cachedLanguageRaw = rawValue
        cachedBundle = resolved
        return resolved
    }

    // MARK: - Common

    static var delete: String { String(localized: "Delete", bundle: bundle) }
    static var rename: String { String(localized: "Rename", bundle: bundle) }
    static var create: String { String(localized: "Create", bundle: bundle) }

    // MARK: - Sidebar

    static var newProject: String { String(localized: "New Project", bundle: bundle) }
    static var projectName: String { String(localized: "Project Name", bundle: bundle) }
    static var editContext: String { String(localized: "Edit Context", bundle: bundle) }
    static var openInFinder: String { String(localized: "Open in Finder", bundle: bundle) }
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

    // MARK: - Detail Tabs

    static var summary: String { String(localized: "Summary", bundle: bundle) }
    static var notes: String { String(localized: "Notes", bundle: bundle) }
    static var screenshots: String { String(localized: "Screenshots", bundle: bundle) }
    static var transcript: String { String(localized: "Transcript", bundle: bundle) }

    // MARK: - Audio Source Mode

    static var mic: String { String(localized: "Mic", bundle: bundle) }
    static var system: String { String(localized: "System", bundle: bundle) }
    static var both: String { String(localized: "Both", bundle: bundle) }

    // MARK: - Settings

    static var general: String { String(localized: "General", bundle: bundle) }
    static var aiSummary: String { String(localized: "AI Summary", bundle: bundle) }
    static var editor: String { String(localized: "Editor", bundle: bundle) }
    static var vault: String { String(localized: "Vault", bundle: bundle) }
    static var appLanguage: String { String(localized: "App Language", bundle: bundle) }
    static var appLanguageDescription: String { String(localized: "Set the display language for the app.", bundle: bundle) }
    static var followSystem: String { String(localized: "Follow System", bundle: bundle) }

    // MARK: - Vault Picker

    static var createNewVault: String { String(localized: "Create New Vault", bundle: bundle) }
    static var createNewVaultDescription: String { String(localized: "Create a new folder to use as a vault.", bundle: bundle) }
    static var openFolderAsVault: String { String(localized: "Open Folder as Vault", bundle: bundle) }
    static var openFolderAsVaultDescription: String { String(localized: "Select an existing folder to use as a vault.", bundle: bundle) }
    static var removeVault: String { String(localized: "Remove Vault", bundle: bundle) }
    static var open: String { String(localized: "Open", bundle: bundle) }
    static var loadingLanguages: String { String(localized: "Loading supported languages...", bundle: bundle) }
    static var searchLanguages: String { String(localized: "Search languages...", bundle: bundle) }
    static var noMatchingLanguages: String { String(localized: "No matching languages", bundle: bundle) }
    static var allLanguagesShown: String { String(localized: "All languages shown", bundle: bundle) }
    static func languagesSelected(_ count: Int) -> String { String(localized: "\(count) languages selected", bundle: bundle) }
    static var showAll: String { String(localized: "Show all", bundle: bundle) }
    static var uncheckAll: String { String(localized: "Uncheck all", bundle: bundle) }
    static var displayLanguages: String { String(localized: "Display Languages", bundle: bundle) }
    static var displayLanguagesDescription: String { String(
        localized: "Only selected languages will appear in the language picker. All languages are shown if none are selected.",
        bundle: bundle
    ) }

    // MARK: - Settings (Markdown Editor)

    static var markdownEditor: String { String(localized: "Markdown Editor", bundle: bundle) }
    static var markdownEditorDescription: String { String(localized: "Editor used to open context and summary files.", bundle: bundle) }
    static var systemDefault: String { String(localized: "System Default", bundle: bundle) }

    // MARK: - Settings (LLM)

    static var model: String { String(localized: "Model", bundle: bundle) }
    static var templates: String { String(localized: "Templates", bundle: bundle) }
    static var llmSettings: String { String(localized: "LLM Settings", bundle: bundle) }
    static var endpointURL: String { String(localized: "Endpoint URL", bundle: bundle) }
    static var modelName: String { String(localized: "Model Name", bundle: bundle) }
    static var apiToken: String { String(localized: "API Token", bundle: bundle) }
    static var apiTokenStoredInKeychain: String { String(localized: "Token is stored securely in Keychain.", bundle: bundle) }
    static var autoSummary: String { String(localized: "Auto-Summary", bundle: bundle) }
    static var autoSummaryDescription: String { String(localized: "Automatically generate a summary when transcription stops.", bundle: bundle) }
    static var llmSettingsDescription: String { String(localized: "Configure an LLM endpoint for post-transcription summarization.", bundle: bundle) }
    static var testConnection: String { String(localized: "Test Connection", bundle: bundle) }
    static var testing: String { String(localized: "Testing...", bundle: bundle) }
    static var connectionSuccess: String { String(localized: "Connection successful", bundle: bundle) }
    static var llmErrorInvalidURL: String { String(localized: "Invalid endpoint URL", bundle: bundle) }
    static var llmErrorUnexpectedResponse: String { String(localized: "Unexpected response from server", bundle: bundle) }
    static func llmErrorHTTP(_ code: Int, _ detail: String) -> String { String(localized: "HTTP \(code): \(detail)", bundle: bundle) }
    static var llmErrorEmptyResponse: String { String(localized: "Empty response from server", bundle: bundle) }

    // MARK: - Summary

    static var generatingSummary: String { String(localized: "Generating summary...", bundle: bundle) }
    static var summaryGenerated: String { String(localized: "Summary generated", bundle: bundle) }
    static var openSummary: String { String(localized: "Open Summary", bundle: bundle) }
    static var generateSummary: String { String(localized: "Generate Summary", bundle: bundle) }
    static var summaryPrompt: String { String(localized: "Summary Prompt", bundle: bundle) }
    static var resetToDefault: String { String(localized: "Reset to Default", bundle: bundle) }
    static var summaryTemplate: String { String(localized: "Summary Template", bundle: bundle) }
    static var openInEditor: String { String(localized: "Open in Editor", bundle: bundle) }
    static var openTemplatesFolder: String { String(localized: "Open Templates Folder", bundle: bundle) }
    static var resetPresets: String { String(localized: "Reset Presets", bundle: bundle) }
    static var summaryTemplateDescription: String { String(localized: "Select a template from _custom_instructions/ in the vault.", bundle: bundle) }
    static var llmConfigIncomplete: String { String(
        localized: "LLM configuration is incomplete. Please set endpoint, model, and API token in Settings.",
        bundle: bundle
    ) }

    // MARK: - Error Messages (Audio)

    static var screenRecordingDenied: String { String(
        localized: "Screen recording access denied. Please allow it in System Settings > Privacy & Security > Screen Recording.",
        bundle: bundle
    ) }
    static var noDisplayFound: String { String(localized: "No available displays found", bundle: bundle) }
    static var invalidHardwareFormat: String { String(localized: "Invalid audio hardware format", bundle: bundle) }
    static var converterCreationFailed: String { String(localized: "Failed to create audio format converter", bundle: bundle) }
    static var microphoneDenied: String { String(
        localized: "Microphone access denied. Please allow it in System Settings > Privacy & Security > Microphone.",
        bundle: bundle
    ) }

    // MARK: - Error Messages (ViewModel)

    static var speechRecognitionUnavailable: String { String(localized: "Speech recognition is not available on this Mac", bundle: bundle) }
    static func speechPreparationFailed(_ error: String) -> String { String(
        localized: "Failed to prepare speech recognition: \(error)",
        bundle: bundle
    ) }
    static func languageChangeFailed(_ error: String) -> String { String(localized: "Failed to change language: \(error)", bundle: bundle) }
    static var speechRecognitionNotReady: String { String(localized: "Speech recognition is not ready", bundle: bundle) }
    static var systemAudioCaptureStopped: String { String(localized: "System audio capture stopped", bundle: bundle) }

    // MARK: - Sidebar Footer

    static var switchVault: String { String(localized: "Switch Vault", bundle: bundle) }
    static var manageVaults: String { String(localized: "Manage Vaults...", bundle: bundle) }
    static var settings: String { String(localized: "Settings", bundle: bundle) }

    // MARK: - Meeting Detection

    static var meetingDetection: String { String(localized: "Meeting Detection", bundle: bundle) }
    static var meetingDetectionDescription: String { String(
        localized: "Show a prompt when a video meeting is detected.",
        bundle: bundle
    ) }
    static func meetingDetectedMessage(_ appName: String) -> String { String(
        localized: "Meeting detected (\(appName)). Start transcription?",
        bundle: bundle
    ) }
    static var startTranscription: String { String(localized: "Start Transcription", bundle: bundle) }
    static var dismiss: String { String(localized: "Dismiss", bundle: bundle) }
    static func meetingDetectedSubtitle(_ appName: String) -> String { String(
        localized: "Meeting detected in \(appName)",
        bundle: bundle
    ) }
    static var microphoneInUse: String { String(localized: "Microphone is in use", bundle: bundle) }

    // MARK: - Keychain

    static var keychainAuthReason: String { String(localized: "Authenticate to access your API token stored in Keychain.", bundle: bundle) }
}
