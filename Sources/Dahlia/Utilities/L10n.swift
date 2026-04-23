import Foundation

/// ローカライズ文字列への型安全なアクセスを提供する。
enum L10n {
    /// キャッシュ済みの Bundle と、その生成元の言語 rawValue。
    /// 言語設定が変わらない限り Bundle を再生成しない。
    private nonisolated(unsafe) static var cachedBundle: Bundle = .appModule
    private nonisolated(unsafe) static var cachedLanguageRaw = ""

    /// 選択された表示言語に対応する Bundle を返す。
    /// UserDefaults から直接読み取ることで @MainActor 制約を回避する。
    private nonisolated static var bundle: Bundle {
        let rawValue = UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey) ?? AppLanguage.system.rawValue
        if rawValue == cachedLanguageRaw { return cachedBundle }
        let resolved: Bundle = if let language = AppLanguage(rawValue: rawValue),
                                  let lprojName = language.lprojName,
                                  let path = Bundle.appModule.path(forResource: lprojName, ofType: "lproj"),
                                  let lprojBundle = Bundle(path: path) {
            lprojBundle
        } else {
            .appModule
        }
        cachedLanguageRaw = rawValue
        cachedBundle = resolved
        return resolved
    }

    // MARK: - Common

    static var delete: String { String(localized: "Delete", bundle: bundle) }
    static var rename: String { String(localized: "Rename", bundle: bundle) }
    static var create: String { String(localized: "Create", bundle: bundle) }
    static var apply: String { String(localized: "Apply", bundle: bundle) }
    static var clear: String { String(localized: "Clear", bundle: bundle) }
    static var close: String { String(localized: "Close", bundle: bundle) }
    static var search: String { String(localized: "Search", bundle: bundle) }
    static var join: String { String(localized: "Join", bundle: bundle) }
    static var expand: String { String(localized: "Expand", bundle: bundle) }
    static var collapse: String { String(localized: "Collapse", bundle: bundle) }
    static var back: String { String(localized: "Back", bundle: bundle) }
    static var forward: String { String(localized: "Forward", bundle: bundle) }
    static var showSidebar: String { String(localized: "Show Sidebar", bundle: bundle) }
    static var hideSidebar: String { String(localized: "Hide Sidebar", bundle: bundle) }

    // MARK: - Sidebar

    static var home: String { String(localized: "Home", bundle: bundle) }
    static var goodMorning: String { String(localized: "Good morning", bundle: bundle) }
    static var goodAfternoon: String { String(localized: "Good afternoon", bundle: bundle) }
    static var goodEvening: String { String(localized: "Good evening", bundle: bundle) }
    static var meetings: String { String(localized: "Meetings", bundle: bundle) }
    static var projects: String { String(localized: "Projects", bundle: bundle) }
    static var instructions: String { String(localized: "Instructions", bundle: bundle) }
    static var context: String { String(localized: "Context", bundle: bundle) }
    static var actionItems: String { String(localized: "Action Items", bundle: bundle) }
    static var me: String { String(localized: "Me", bundle: bundle) }
    static var ask: String { String(localized: "Ask", bundle: bundle) }
    static var newProject: String { String(localized: "New Project", bundle: bundle) }
    static var newMeeting: String { String(localized: "New meeting", bundle: bundle) }
    static var projectName: String { String(localized: "Project Name", bundle: bundle) }
    static var location: String { String(localized: "Location", bundle: bundle) }
    static var latestMeeting: String { String(localized: "Latest Meeting", bundle: bundle) }
    static var contextCreationFailed: String { String(localized: "Could not create CONTEXT.md.", bundle: bundle) }
    static var openInFinder: String { String(localized: "Open in Finder", bundle: bundle) }
    static var openInObsidian: String { String(localized: "Open in Obsidian", bundle: bundle) }
    static var openInBrowser: String { String(localized: "Open in Browser", bundle: bundle) }
    static var recreateFolder: String { String(localized: "Recreate Folder", bundle: bundle) }
    static var folderMissing: String { String(localized: "Folder missing on disk", bundle: bundle) }
    static var homeUnderConstruction: String { String(localized: "Home is under construction.", bundle: bundle) }
    static var actionItemsComingSoon: String { String(localized: "Action items will appear here.", bundle: bundle) }
    static var selectProjectFromProjects: String { String(localized: "Select a project from Projects.", bundle: bundle) }
    static var openProjects: String { String(localized: "Open Projects", bundle: bundle) }
    static var title: String { String(localized: "Title", bundle: bundle) }
    static var all: String { String(localized: "All", bundle: bundle) }
    static var filter: String { String(localized: "Filter", bundle: bundle) }
    static var searchFilters: String { String(localized: "Search filters...", bundle: bundle) }
    static var tags: String { String(localized: "Tags", bundle: bundle) }
    static var assignedToMe: String { String(localized: "Assigned to me", bundle: bundle) }
    static var completed: String { String(localized: "Completed", bundle: bundle) }
    static var projectIs: String { String(localized: "Project is", bundle: bundle) }
    static var tagIs: String { String(localized: "Tag is", bundle: bundle) }
    static var today: String { String(localized: "Today", bundle: bundle) }
    static var tomorrow: String { String(localized: "Tomorrow", bundle: bundle) }
    static var inProgress: String { String(localized: "In Progress", bundle: bundle) }
    static var noMeetingsYet: String { String(localized: "No meetings yet", bundle: bundle) }
    static var noMeetingsMatchFilter: String { String(localized: "No meetings match the current filter.", bundle: bundle) }
    static var noProjectsYet: String { String(localized: "No projects yet", bundle: bundle) }
    static var noProjectsMatchFilter: String { String(localized: "No projects match the current filter.", bundle: bundle) }
    static var noInstructionsYet: String { String(localized: "No instructions yet", bundle: bundle) }
    static var noActionItemsYet: String { String(localized: "No action items yet", bundle: bundle) }
    static var noActionItemsMatchFilter: String { String(localized: "No action items match the current filter.", bundle: bundle) }
    static var actionItemsDescription: String { String(localized: "Action items extracted from summaries will appear here.", bundle: bundle) }
    static var missingOnDisk: String { String(localized: "Missing on Disk", bundle: bundle) }
    static func meetingCount(_ count: Int) -> String { String(localized: "\(count) meetings", bundle: bundle) }
    static var noMeetings: String { String(localized: "No meetings", bundle: bundle) }
    static var noConversationDetected: String { String(localized: "We couldn't detect any conversation in this meeting.", bundle: bundle) }
    static var recordingNow: String { String(localized: "Recording now", bundle: bundle) }
    static var yesterday: String { String(localized: "Yesterday", bundle: bundle) }
    static func deleteCount(_ count: Int) -> String { String(localized: "Delete \(count) items", bundle: bundle) }
    static func moveCount(_ count: Int) -> String { String(localized: "Move \(count) items", bundle: bundle) }
    static func selectedCount(_ count: Int) -> String { String(localized: "\(count) selected", bundle: bundle) }

    // MARK: - Meeting Metadata

    static var addTag: String { String(localized: "Add tag", bundle: bundle) }
    static var searchOrCreateTag: String { String(localized: "Search or create tag...", bundle: bundle) }
    static var searchOrCreateProject: String { String(localized: "Search or create project...", bundle: bundle) }
    static var addInstruction: String { String(localized: "Add Instruction", bundle: bundle) }
    static var addInstructionDescription: String { String(localized: "Create your first instruction to customize summary output.", bundle: bundle) }
    static var selectInstruction: String { String(localized: "Select Instruction", bundle: bundle) }
    static var selectInstructionDescription: String { String(localized: "Select an instruction to edit.", bundle: bundle) }
    static var useForSummary: String { String(localized: "Use for Summary", bundle: bundle) }
    static var useAutoInstructions: String { String(localized: "Use Auto", bundle: bundle) }
    static var summaryInstructionSelected: String { String(localized: "This instruction is currently used for summary generation.", bundle: bundle) }
    static var summaryInstructionNotSelected: String { String(
        localized: "This instruction is not currently used for summary generation.",
        bundle: bundle
    ) }
    static var instructionsEmptyContent: String { String(localized: "No content yet", bundle: bundle) }
    static var noResultsFound: String { String(localized: "No results found", bundle: bundle) }
    static var noProject: String { String(localized: "No project", bundle: bundle) }

    // MARK: - Control Panel

    static var audioSource: String { String(localized: "Audio source", bundle: bundle) }
    static var preparingSpeechRecognition: String { String(localized: "Preparing speech recognition...", bundle: bundle) }
    static var recognizing: String { String(localized: "Recognizing...", bundle: bundle) }
    static var transcription: String { String(localized: "Transcription", bundle: bundle) }
    static func segmentCount(_ count: Int) -> String { String(localized: "\(count) segments", bundle: bundle) }
    static var stop: String { String(localized: "Stop", bundle: bundle) }
    static var pause: String { String(localized: "Pause", bundle: bundle) }
    static var resume: String { String(localized: "Resume", bundle: bundle) }
    static var record: String { String(localized: "Record", bundle: bundle) }
    static var export: String { String(localized: "Export", bundle: bundle) }
    static var clearTranscription: String { String(localized: "Clear transcription", bundle: bundle) }
    static var newTranscription: String { String(localized: "New Transcription", bundle: bundle) }
    static var screen: String { String(localized: "Screen", bundle: bundle) }
    static var source: String { String(localized: "Source", bundle: bundle) }
    static var showLiveSubtitles: String { String(localized: "Show Live Subtitles", bundle: bundle) }
    static var hideLiveSubtitles: String { String(localized: "Hide Live Subtitles", bundle: bundle) }
    static var liveSubtitleOverlay: String { String(localized: "Live Subtitle Overlay", bundle: bundle) }
    static var liveSubtitleOverlayDescription: String { String(
        localized: "Configure how the desktop live subtitle overlay is shown while recording.",
        bundle: bundle
    ) }
    static var subtitles: String { String(localized: "Subtitles", bundle: bundle) }
    static var systemAudioOnly: String { String(localized: "System Audio Only", bundle: bundle) }
    static var includeMicrophone: String { String(localized: "Include Microphone", bundle: bundle) }
    static var liveSubtitleSourceDescription: String { String(
        localized: "Choose whether live subtitles only show system audio or also include microphone input.",
        bundle: bundle
    ) }
    static var liveSubtitleOverlaySegmentCount: String { String(localized: "Overlay Segment Count", bundle: bundle) }
    static var liveSubtitleOverlaySegmentCountDescription: String { String(
        localized: "Choose how many recent transcript segments the live subtitle overlay shows.",
        bundle: bundle
    ) }

    // MARK: - Detail Tabs

    static var summary: String { String(localized: "Summary", bundle: bundle) }
    static var notes: String { String(localized: "Notes", bundle: bundle) }
    static var notesPlaceholder: String { String(localized: "NotesPlaceholder", bundle: bundle) }
    static var screenshots: String { String(localized: "Screenshots", bundle: bundle) }
    static var transcript: String { String(localized: "Transcript", bundle: bundle) }
    static var agent: String { String(localized: "Agent", bundle: bundle) }
    static var assignee: String { String(localized: "Assignee", bundle: bundle) }
    static var assignToMe: String { String(localized: "Assign to me", bundle: bundle) }
    static var editAssignee: String { String(localized: "Edit assignee", bundle: bundle) }
    static var markActionItemComplete: String { String(localized: "Mark action item complete", bundle: bundle) }
    static var markActionItemIncomplete: String { String(localized: "Mark action item incomplete", bundle: bundle) }

    // MARK: - Agent

    static var agentProjectMode: String { String(localized: "Project Mode", bundle: bundle) }
    static var agentTranscriptMode: String { String(localized: "Transcript Mode", bundle: bundle) }
    static var agentProjectModeDescription: String { String(
        localized: "Run the configured agent command in the project directory.",
        bundle: bundle
    ) }
    static var agentTranscriptModeDescription: String { String(
        localized: "Continuously feed transcript to the configured agent command.",
        bundle: bundle
    ) }
    static var askAgent: String { String(localized: "Ask Agent", bundle: bundle) }
    static var agentAskPlaceholder: String { String(
        localized: "Ask anything about your project or transcript…",
        bundle: bundle
    ) }
    static var newChat: String { String(localized: "New chat", bundle: bundle) }
    static var startAgent: String { String(localized: "Start Agent", bundle: bundle) }
    static var stopAgent: String { String(localized: "Stop Agent", bundle: bundle) }
    static var agentLaunching: String { String(localized: "Launching agent…", bundle: bundle) }
    static var agentLiveMode: String { String(localized: "Live mode", bundle: bundle) }
    static var agentProcessing: String { String(localized: "Thinking…", bundle: bundle) }

    // MARK: - Settings (Agent)

    static var agentLaunchCommand: String { String(localized: "Launch Command", bundle: bundle) }
    static var agentLaunchCommandDescription: String { String(
        localized: "Command used to launch the agent. Default: `claude`. A full path is optional when the executable is available in PATH or common user bin directories.",
        bundle: bundle
    ) }
    static var agentPermissionMode: String { String(localized: "Permission Mode", bundle: bundle) }
    static var agentPermissionModeDescription: String { String(
        localized: "Choose how the agent handles permission prompts when using tools and editing files.",
        bundle: bundle
    ) }
    static var agentPermissionModeAuto: String { String(localized: "Auto", bundle: bundle) }
    static var agentPermissionModeDefault: String { String(localized: "Default", bundle: bundle) }
    static var agentPermissionModeAcceptEdits: String { String(localized: "Accept Edits", bundle: bundle) }
    static var agentPermissionModeBypassPermissions: String { String(localized: "Bypass Permissions", bundle: bundle) }
    static var agentAllowedTools: String { String(localized: "Allowed Tools", bundle: bundle) }
    static var agentAllowedToolsDescription: String { String(
        localized: "Space-separated tool allowlist passed to the agent CLI. Leave blank to use the default set.",
        bundle: bundle
    ) }
    static var agentAllowedToolsPlaceholder: String { String(
        localized: "Add a tool and press Space",
        bundle: bundle
    ) }
    static func agentAllowedToolsRemoveToken(_ token: String) -> String { String(localized: "Remove \(token)", bundle: bundle) }

    // MARK: - Audio Source Mode

    static var microphone: String { String(localized: "Microphone", bundle: bundle) }
    static var mic: String { String(localized: "Mic", bundle: bundle) }
    static var system: String { String(localized: "System", bundle: bundle) }
    static var systemAudio: String { String(localized: "System Audio", bundle: bundle) }
    static var both: String { String(localized: "Both", bundle: bundle) }
    static var none: String { String(localized: "None", bundle: bundle) }
    static var sameAsSystem: String { String(localized: "Same as System", bundle: bundle) }
    static func sameAsSystem(_ deviceName: String) -> String { String(localized: "Same as System (\(deviceName))", bundle: bundle) }
    static var noComputerAudio: String { String(localized: "No computer audio", bundle: bundle) }
    static var recordComputerAudio: String { String(localized: "Record computer audio", bundle: bundle) }

    // MARK: - Settings

    static var general: String { String(localized: "General", bundle: bundle) }
    static var notifications: String { String(localized: "Notifications", bundle: bundle) }
    static var calendar: String { String(localized: "Calendar", bundle: bundle) }
    static var cloudStorage: String { String(localized: "Cloud Storage", bundle: bundle) }
    static var aiSummary: String { String(localized: "AI Summary", bundle: bundle) }
    static var aiAgent: String { String(localized: "AI Agent", bundle: bundle) }
    static var vault: String { String(localized: "Vault", bundle: bundle) }
    static var appearance: String { String(localized: "Appearance", bundle: bundle) }
    static var display: String { String(localized: "Display", bundle: bundle) }
    static var appLanguage: String { String(localized: "App Language", bundle: bundle) }
    static var appLanguageDescription: String { String(localized: "Set the display language for the app.", bundle: bundle) }
    static var followSystem: String { String(localized: "Follow System", bundle: bundle) }
    static var notificationSettingsDescription: String { String(
        localized: "Manage meeting detection prompts and related notification behavior.",
        bundle: bundle
    ) }
    static var transcriptionSettingsDescription: String { String(
        localized: "Choose which languages appear when starting transcription.",
        bundle: bundle
    ) }
    static var transcriptTranslation: String { String(localized: "Transcript Translation", bundle: bundle) }
    static var transcriptTranslationDescription: String { String(
        localized: "Show translated transcript lines in the selected target language when available.",
        bundle: bundle
    ) }
    static var translationTargetLanguage: String { String(localized: "Target Language", bundle: bundle) }
    static var translationTargetLanguageDescription: String { String(
        localized: "Choose which language translated transcript lines should use.",
        bundle: bundle
    ) }
    static var translationDisabledForMatchingLanguage: String { String(
        localized: "Translation is automatically disabled when the target language matches the transcription language.",
        bundle: bundle
    ) }
    static var aiSummarySettingsDescription: String { String(
        localized: "Configure automatic summaries and the LLM connection used to generate them.",
        bundle: bundle
    ) }
    static var agentSettingsDescription: String { String(
        localized: "Configure the built-in agent sidebar launch command and permission mode.",
        bundle: bundle
    ) }
    static var connectionDiagnosticsDescription: String { String(
        localized: "Run a quick request to validate your endpoint, model, and token.",
        bundle: bundle
    ) }
    static var googleCalendar: String { String(localized: "Google Calendar", bundle: bundle) }
    static var googleDrive: String { String(localized: "Google Drive", bundle: bundle) }
    static var googleCalendarSettingsDescription: String { String(
        localized: "Connect a Google account and choose which calendars appear on Home.",
        bundle: bundle
    ) }
    static var googleDriveSettingsDescription: String { String(
        localized: "Connect a Google account to export summaries to Google Drive. Destination folders are configured per project.",
        bundle: bundle
    ) }
    static var googleCalendarDisplayCalendars: String { String(localized: "Display Calendars", bundle: bundle) }
    static var googleCalendarDisplayCalendarsDescription: String { String(
        localized: "Only selected calendars are shown on Home.",
        bundle: bundle
    ) }
    static var googleCalendarConnect: String { String(localized: "Connect", bundle: bundle) }
    static var googleCalendarDisconnect: String { String(localized: "Disconnect", bundle: bundle) }
    static var googleCalendarConnectDescription: String { String(
        localized: "Sign in with Google to load your upcoming schedule.",
        bundle: bundle
    ) }
    static var googleCalendarConnected: String { String(localized: "Connected", bundle: bundle) }
    static var googleCalendarNotConnected: String { String(localized: "No Google account connected", bundle: bundle) }
    static var googleDriveConnect: String { googleCalendarConnect }
    static var googleDriveDisconnect: String { googleCalendarDisconnect }
    static var googleDriveConnectDescription: String { String(
        localized: "Sign in with Google to choose project folders and export summaries.",
        bundle: bundle
    ) }
    static var googleDriveConnected: String { String(localized: "Google Drive connected", bundle: bundle) }
    static var googleDriveNotConnected: String { String(localized: "No Google Drive account connected", bundle: bundle) }
    static var googleCalendarPrimaryCalendar: String { String(localized: "Primary calendar", bundle: bundle) }
    static var googleCalendarNoCalendars: String { String(localized: "No calendars are available for this Google account.", bundle: bundle) }
    static var googleCalendarLoading: String { String(localized: "Loading Google Calendar…", bundle: bundle) }
    static var googleDriveLoadingFolders: String { String(localized: "Loading Google Drive folders…", bundle: bundle) }
    static var googleCalendarRetry: String { String(localized: "Retry", bundle: bundle) }
    static var googleCalendarAllDay: String { String(localized: "All day", bundle: bundle) }
    static var googleCalendarClientIDMissingTitle: String { String(localized: "Google Calendar is not configured", bundle: bundle) }
    static var googleCalendarClientIDMissingMessage: String { String(
        localized: "Set GOOGLE_CLIENT_ID before connecting Google Calendar.",
        bundle: bundle
    ) }
    static var googleCalendarSignInRequiredTitle: String { String(localized: "Connect Google Calendar", bundle: bundle) }
    static var googleCalendarSignInRequiredMessage: String { String(
        localized: "Connect Google Calendar from Settings to show your upcoming events on Home.",
        bundle: bundle
    ) }
    static var googleCalendarSelectionRequiredTitle: String { String(localized: "Choose calendars to show", bundle: bundle) }
    static var googleCalendarSelectionRequiredMessage: String { String(
        localized: "Select at least one calendar in Settings to show events on Home.",
        bundle: bundle
    ) }
    static var googleCalendarNoUpcomingEventsTitle: String { String(localized: "No upcoming events", bundle: bundle) }
    static var googleCalendarNoUpcomingEventsMessage: String { String(
        localized: "There are no events in the next 7 days for the selected calendars.",
        bundle: bundle
    ) }
    static var googleCalendarLoadFailedTitle: String { String(localized: "Could not load Google Calendar", bundle: bundle) }
    static var googleCalendarMissingPresentingWindow: String { String(
        localized: "No window is available to present Google sign-in.",
        bundle: bundle
    ) }
    static var googleCalendarNoPreviousSession: String { String(localized: "No previous Google Calendar session was found.", bundle: bundle) }
    static var googleAccountNoPreviousSession: String { String(localized: "No previous Google session was found.", bundle: bundle) }
    static var googleCalendarClientSecretMissingMessage: String { String(
        localized: "This Google OAuth client requires a client secret. Set GOOGLE_CLIENT_SECRET to the value from Google Cloud Console and relaunch Dahlia.",
        bundle: bundle
    ) }
    static var googleAccountClientIDMissingMessage: String { String(
        localized: "Set GOOGLE_CLIENT_ID before connecting Google services.",
        bundle: bundle
    ) }
    static var googleAccountClientSecretMissingMessage: String { googleCalendarClientSecretMissingMessage }
    static var googleCalendarKeychainConfigurationMessage: String { String(
        localized: "Google sign-in could not access Keychain. Rebuild the app with ./scripts/run-dev.sh so it is code signed with the required Keychain entitlements.",
        bundle: bundle
    ) }
    static var googleAccountKeychainConfigurationMessage: String { googleCalendarKeychainConfigurationMessage }
    static var googleCalendarUnknownAccount: String { String(localized: "Google Account", bundle: bundle) }
    static var googleAccountUnknown: String { googleCalendarUnknownAccount }
    static var googleAccountMissingPresentingWindow: String { googleCalendarMissingPresentingWindow }
    static var googleAccountUnexpectedResponse: String { String(localized: "Unexpected response from Google", bundle: bundle) }
    static func googleAccountHTTPError(_ code: Int, _ detail: String) -> String { String(
        localized: "Google HTTP \(code): \(detail)",
        bundle: bundle
    ) }
    static var googleAccountConnectedWithoutCalendar: String { String(
        localized: "Google account connected, but Calendar access has not been granted yet.",
        bundle: bundle
    ) }
    static var googleCalendarUntitledEvent: String { String(localized: "Untitled event", bundle: bundle) }
    static var googleCalendarUnexpectedResponse: String { String(localized: "Unexpected response from Google Calendar", bundle: bundle) }
    static func googleCalendarHTTPError(_ code: Int, _ detail: String) -> String { String(
        localized: "Google Calendar HTTP \(code): \(detail)",
        bundle: bundle
    ) }
    static func googleCalendarInvalidDate(_ value: String) -> String { String(
        localized: "Could not parse Google Calendar date: \(value)",
        bundle: bundle
    ) }
    static var googleDriveFolderUnavailable: String { String(
        localized: "This Google Drive folder is unavailable or you no longer have access to it.",
        bundle: bundle
    ) }
    static var googleDriveUnexpectedResponse: String { String(localized: "Unexpected response from Google Drive", bundle: bundle) }
    static func googleDriveHTTPError(_ code: Int, _ detail: String) -> String { String(
        localized: "Google Drive HTTP \(code): \(detail)",
        bundle: bundle
    ) }
    static var googleDriveSearchPlaceholder: String { String(localized: "Search Google Drive folders...", bundle: bundle) }
    static var googleDriveFolderPickerDescription: String { String(
        localized: "Search My Drive and shared drives, then choose the folder where summaries should be uploaded.",
        bundle: bundle
    ) }
    static var googleDriveRecent: String { String(localized: "Recent", bundle: bundle) }
    static var googleDriveMyDrive: String { String(localized: "My Drive", bundle: bundle) }
    static var googleDriveSharedDrives: String { String(localized: "Shared drives", bundle: bundle) }
    static var googleDriveSharedDriveLabel: String { String(localized: "Shared drive", bundle: bundle) }
    static var googleDriveNoFolders: String { String(localized: "No folders found", bundle: bundle) }
    static var googleDriveNoFoldersInLocation: String { String(localized: "No folders in this location", bundle: bundle) }
    static var googleDriveNoFolderSelected: String { String(localized: "No Google Drive folder selected", bundle: bundle) }
    static var chooseFolder: String { String(localized: "Choose Folder", bundle: bundle) }
    static var changeFolder: String { String(localized: "Change Folder", bundle: bundle) }
    static var selectFolder: String { String(localized: "Select This Folder", bundle: bundle) }
    static var googleDriveExportFailed: String { String(
        localized: "The summary was saved locally, but uploading to Google Drive failed.",
        bundle: bundle
    ) }

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
    static var microphoneUnavailable: String { String(localized: "The selected microphone is unavailable", bundle: bundle) }
    static var noAudioSourceSelected: String { String(localized: "Select at least one audio source", bundle: bundle) }

    // MARK: - Error Messages (ViewModel)

    static var speechRecognitionUnavailable: String { String(localized: "Speech recognition is not available on this Mac", bundle: bundle) }
    static func speechPreparationFailed(_ error: String) -> String { String(
        localized: "Failed to prepare speech recognition: \(error)",
        bundle: bundle
    ) }
    static func languageChangeFailed(_ error: String) -> String { String(localized: "Failed to change language: \(error)", bundle: bundle) }
    static func actionItemAssigneeUpdateFailed(_ error: String) -> String { String(
        localized: "Could not update action item assignee: \(error)",
        bundle: bundle
    ) }
    static func actionItemDeleteFailed(_ error: String) -> String { String(localized: "Could not delete action item: \(error)", bundle: bundle) }
    static func actionItemUpdateFailed(_ error: String) -> String { String(localized: "Could not update action item: \(error)", bundle: bundle) }
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
    static var startTranscribing: String { String(localized: "Start transcribing", bundle: bundle) }
    static var manageNotificationSettings: String { String(localized: "Manage notification settings", bundle: bundle) }
    static var dismiss: String { String(localized: "Dismiss", bundle: bundle) }
    static var meetingDetected: String { String(localized: "Meeting detected", bundle: bundle) }
    static func meetingDetectedSubtitle(_ appName: String) -> String { String(
        localized: "Meeting detected in \(appName)",
        bundle: bundle
    ) }
    static var microphoneInUse: String { String(localized: "Microphone is in use", bundle: bundle) }

    // MARK: - Keychain

    static var keychainAuthReason: String { String(localized: "Authenticate to access your API token stored in Keychain.", bundle: bundle) }
}
