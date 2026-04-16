import Combine
import CoreAudio
import GRDB
import os
@preconcurrency import ScreenCaptureKit
import Speech
import SwiftUI

private enum ScreenshotError: Error {
    case encodingFailed
    case imageUnavailable
}

/// 録音中のナビゲーション時に保持する録音コンテキスト。
private struct RecordingContext {
    let meetingId: UUID?
    let store: TranscriptStore
    let projectURL: URL?
    let projectId: UUID?
    let projectName: String?
    let vaultURL: URL?
    let dbQueue: DatabaseQueue?
}

/// 音声キャプチャ → Speech フレームワーク文字起こし → UI 更新を統括するビューモデル。
@MainActor
final class CaptionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var store = TranscriptStore()
    @Published var isListening = false
    @Published var analyzerReady = false
    @Published var isPreparingAnalyzer = false
    @Published var errorMessage: String?
    @Published var availableMicrophones: [MicrophoneDevice] = []
    @Published var selectedMicrophoneID: AudioDeviceID? = AudioCaptureManager.defaultInputDeviceID()
    @Published var isSystemAudioEnabled = true
    @Published var selectedLocale: String = AppSettings.shared.transcriptionLocale
    @Published var supportedLocales: [Locale] = []
    @Published var filteredLocales: [Locale] = []

    // MARK: - Meeting State

    var currentMeetingId: UUID?
    var currentProjectURL: URL?
    var currentProjectId: UUID?
    var currentProjectName: String?
    var currentVaultURL: URL?

    // MARK: - Summary State

    @Published var summaryGeneratingMeetingId: UUID?
    var isSummaryGenerating: Bool { summaryGeneratingMeetingId != nil }
    @Published var summaryError: String?
    @Published var lastSummaryURL: URL?
    @Published var currentMeetingSummary: String?
    @Published var currentMeetingActionItems: [ActionItemRecord] = []
    /// Summary タブへの切り替えをリクエストするフラグ。
    @Published var requestShowSummaryTab = false
    /// 要約生成の進捗トースト状態。
    let summaryProgress = SummaryProgressState()

    // MARK: - Agent State

    @Published var agentService: AgentService?

    // MARK: - Note State

    @Published var noteText = ""
    private var hasNote = false
    private var currentNoteCreatedAt: Date?
    private var noteAutoSaveCancellable: AnyCancellable?
    private var lastSavedNoteText: String?

    // MARK: - Screenshot State

    @Published var screenshots: [MeetingScreenshotRecord] = []
    /// キャプチャ対象として選択可能なウィンドウ一覧。
    @Published var availableWindows: [SCWindow] = []
    /// 選択中のウィンドウ ID。nil の場合はデスクトップ全体をキャプチャ。
    @Published var selectedWindowID: CGWindowID?

    var hasCurrentMeetingSummary: Bool {
        guard let currentMeetingSummary else { return false }
        return !currentMeetingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sanitizedMeetingSummary: String? {
        guard let currentMeetingSummary else { return nil }
        let sanitized = SummaryService.sanitizeDisplaySummary(currentMeetingSummary)
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sanitized
    }

    var orderedCurrentMeetingActionItems: [ActionItemRecord] {
        currentMeetingActionItems.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            if lhs.sortsAsMine != rhs.sortsAsMine {
                return lhs.sortsAsMine && !rhs.sortsAsMine
            }

            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }

            let assigneeOrder = lhs.assignee.localizedCaseInsensitiveCompare(rhs.assignee)
            if assigneeOrder != .orderedSame {
                return assigneeOrder == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// 録音中でなく、文字起こしを表示中の場合 true。
    var isViewingHistory: Bool {
        !isListening && currentMeetingId != nil
    }

    /// マイクが有効か。
    var isMicEnabled: Bool { selectedMicrophoneID != nil }

    /// 少なくとも 1 つの音声ソースが有効か。
    var hasEnabledAudioSource: Bool { isMicEnabled || isSystemAudioEnabled }

    // MARK: - Recording Context (録音中のナビゲーション時に保持)

    /// 録音中に別トランスクリプトへナビゲーションした際の録音コンテキスト。
    private var recordingContext: RecordingContext?

    /// 録音対象の文字起こし ID。
    /// recordingContext 初期化前（録音開始〜別トランスクリプトへ遷移前）は currentMeetingId で補う。
    var recordingMeetingId: UUID? {
        recordingContext?.meetingId ?? (isListening ? currentMeetingId : nil)
    }

    /// 録音中かつ録音対象とは別のトランスクリプトを閲覧中。
    var isViewingOtherWhileRecording: Bool {
        isListening && recordingContext != nil
    }

    var activeMeetingIdForSessionControls: UUID? {
        recordingContext?.meetingId ?? currentMeetingId
    }

    var canTakeScreenshot: Bool {
        activeMeetingIdForSessionControls != nil && activeDbQueueForSessionControls != nil
    }

    // MARK: - Private

    private var currentDbQueue: DatabaseQueue?
    private var audioManager: AudioCaptureManager?
    private var systemAudioManager: SystemAudioCaptureManager?
    private var pipelines: [(service: SpeechTranscriberService, bridge: AudioBufferBridge)] = []
    private var persistenceService: MeetingPersistenceService?
    private var storeCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var meetingLoadTask: Task<Void, Never>?

    private var activeDbQueueForSessionControls: DatabaseQueue? {
        recordingContext?.dbQueue ?? currentDbQueue
    }

    init() {
        resubscribeStoreCancellable()
        refreshAvailableMicrophones()

        // AppSettings の表示言語設定変更を監視
        settingsCancellable = UserDefaults.standard
            .publisher(for: \.enabledLocaleIdentifiers)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateFilteredLocales()
            }
    }

    /// supportedLocales と設定から filteredLocales を再計算する。
    private func updateFilteredLocales() {
        let settings = AppSettings.shared
        let enabled = settings.enabledLocaleIdentifiers
        if enabled.isEmpty {
            filteredLocales = supportedLocales
        } else {
            filteredLocales = supportedLocales.filter { locale in
                enabled.contains(locale.identifier)
                    || locale.identifier == selectedLocale
            }
        }
    }

    func refreshAvailableMicrophones() {
        let devices = AudioCaptureManager.availableInputDevices()

        if devices != availableMicrophones {
            availableMicrophones = devices
        }

        if let currentMicrophoneID = selectedMicrophoneID,
           !devices.contains(where: { $0.id == currentMicrophoneID }) {
            self.selectedMicrophoneID = AudioCaptureManager.defaultInputDeviceID()
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    private struct LoadedMeetingData {
        let createdAt: Date?
        let segments: [TranscriptSegment]
        let screenshots: [MeetingScreenshotRecord]
        let summary: String?
        let actionItems: [ActionItemRecord]
        let lastSummaryURL: URL?
        let note: MeetingNoteRecord?
    }

    private nonisolated static func fetchLoadedMeetingData(
        meetingId: UUID,
        dbQueue: DatabaseQueue,
        projectURL: URL?,
        vaultURL: URL
    ) throws -> LoadedMeetingData {
        let repo = MeetingRepository(dbQueue: dbQueue)
        let detail = try repo.fetchMeetingDetail(id: meetingId)
        let segments = detail.segments.map(TranscriptSegment.init(from:))

        let lastSummaryURL = SummaryService.findSummaryFile(
            projectURL: projectURL,
            vaultURL: vaultURL,
            meetingId: meetingId
        )

        return LoadedMeetingData(
            createdAt: detail.meeting?.createdAt,
            segments: segments,
            screenshots: detail.screenshots,
            summary: detail.summary?.summary,
            actionItems: detail.actionItems,
            lastSummaryURL: lastSummaryURL,
            note: detail.note
        )
    }

    // MARK: - Meeting Loading

    /// DB から文字起こしのセグメントを読み込んで表示する。
    /// 録音中でも呼び出し可能。録音パイプラインはバックグラウンドで継続する。
    func loadMeeting(
        _ meetingId: UUID,
        dbQueue: DatabaseQueue,
        projectURL: URL?,
        projectId: UUID?,
        projectName: String? = nil,
        vaultURL: URL
    ) {
        // 録音中に録音対象のトランスクリプトを選択した場合はライブ表示に復帰
        if isListening, meetingId == recordingMeetingId {
            returnToRecordingMeeting()
            return
        }

        // 録音中の場合、録音コンテキストをバックアップして表示用ストアを差し替え
        if isListening {
            saveRecordingContextIfNeeded()
            meetingLoadTask?.cancel()
            saveNoteImmediately()
            store = TranscriptStore()
            resubscribeStoreCancellable()
        } else {
            resetMeetingState()
        }

        setMeetingContext(
            id: meetingId,
            dbQueue: dbQueue,
            projectURL: projectURL,
            projectId: projectId,
            projectName: projectName,
            vaultURL: vaultURL
        )

        meetingLoadTask = Task { [weak self, meetingId, dbQueue, projectURL, vaultURL] in
            guard let self else { return }

            let loaded: LoadedMeetingData
            do {
                loaded = try await Task.detached(priority: .userInitiated) {
                    try Self.fetchLoadedMeetingData(
                        meetingId: meetingId,
                        dbQueue: dbQueue,
                        projectURL: projectURL,
                        vaultURL: vaultURL
                    )
                }.value
            } catch is CancellationError {
                return
            } catch {
                Logger(subsystem: "com.dahlia", category: "CaptionViewModel")
                    .error("Failed to load meeting \(meetingId): \(error)")
                ErrorReportingService.capture(error, context: ["source": "loadMeeting"])
                return
            }

            guard !Task.isCancelled, self.currentMeetingId == meetingId else { return }

            self.store.recordingStartTime = loaded.createdAt
            self.store.loadSegments(loaded.segments)
            self.applyLoadedDetail(loaded)
        }
    }

    /// 文字起こしを開始せずに空の MeetingRecord を作成し、表示対象としてセットする。
    func createEmptyMeeting(
        dbQueue: DatabaseQueue,
        projectURL: URL?,
        vaultId: UUID,
        projectId: UUID?,
        name: String = "",
        projectName: String? = nil,
        vaultURL: URL
    ) {
        resetMeetingState()

        let meetingId = UUID.v7()
        let now = Date()
        let record = MeetingRecord(
            id: meetingId,
            vaultId: vaultId,
            projectId: projectId,
            name: name,
            createdAt: now,
            updatedAt: now
        )
        try? dbQueue.write { db in
            try record.insert(db)
        }

        setMeetingContext(
            id: meetingId,
            dbQueue: dbQueue,
            projectURL: projectURL,
            projectId: projectId,
            projectName: projectName,
            vaultURL: vaultURL
        )
    }

    /// 現在の文字起こし表示をクリアして初期状態に戻す。
    /// 録音中はバックグラウンド録音を維持したまま表示のみクリアする。
    func clearCurrentMeeting() {
        if isListening {
            saveRecordingContextIfNeeded()
            store = TranscriptStore()
            resubscribeStoreCancellable()
            screenshots = []
            resetNoteState()
            resetSummaryState()
        } else {
            resetMeetingState()
        }
        currentMeetingId = nil
        currentProjectURL = nil
        currentProjectId = nil
        currentProjectName = nil
        currentVaultURL = nil
    }

    /// 録音対象のトランスクリプトに表示を復帰する。
    func returnToRecordingMeeting() {
        guard let ctx = recordingContext else { return }
        meetingLoadTask?.cancel()
        saveNoteImmediately()

        // コンテキストを先に復元（store 代入時の objectWillChange で SwiftUI が再評価する際に
        // currentMeetingId 等が正しい値を返すようにする）
        currentMeetingId = ctx.meetingId
        currentProjectURL = ctx.projectURL
        currentProjectId = ctx.projectId
        currentProjectName = ctx.projectName
        currentVaultURL = ctx.vaultURL
        currentDbQueue = ctx.dbQueue

        store = ctx.store
        resubscribeStoreCancellable()
        recordingContext = nil

        reloadMeetingDetail()
    }

    /// 現在の meetingId のノート・スクリーンショット・サマリーを DB から読み込み直す。
    private func reloadMeetingDetail() {
        guard let meetingId = currentMeetingId,
              let dbQueue = currentDbQueue,
              let vaultURL = currentVaultURL else { return }
        let projectURL = currentProjectURL
        meetingLoadTask = Task { [weak self, meetingId, dbQueue, projectURL, vaultURL] in
            guard let self else { return }
            let loaded: LoadedMeetingData
            do {
                loaded = try await Task.detached(priority: .userInitiated) {
                    try Self.fetchLoadedMeetingData(
                        meetingId: meetingId,
                        dbQueue: dbQueue,
                        projectURL: projectURL,
                        vaultURL: vaultURL
                    )
                }.value
            } catch {
                return
            }
            guard !Task.isCancelled, self.currentMeetingId == meetingId else { return }
            self.applyLoadedDetail(loaded)
        }
    }

    /// 読み込み済みデータのノート・スクリーンショット・サマリーを UI 状態に反映する。
    private func applyLoadedDetail(_ loaded: LoadedMeetingData) {
        screenshots = loaded.screenshots
        currentMeetingSummary = loaded.summary
        currentMeetingActionItems = loaded.actionItems
        lastSummaryURL = loaded.lastSummaryURL
        noteText = loaded.note?.text ?? ""
        hasNote = loaded.note != nil
        currentNoteCreatedAt = loaded.note?.createdAt
        lastSavedNoteText = noteText
        setupNoteAutoSave()
    }

    // MARK: - Private Helpers

    /// 録音コンテキストをバックアップする（初回ナビゲーション時のみ）。
    private func saveRecordingContextIfNeeded() {
        guard recordingContext == nil else { return }
        recordingContext = RecordingContext(
            meetingId: currentMeetingId,
            store: store,
            projectURL: currentProjectURL,
            projectId: currentProjectId,
            projectName: currentProjectName,
            vaultURL: currentVaultURL,
            dbQueue: currentDbQueue
        )
    }

    /// storeCancellable を現在の store に再接続する。
    private func resubscribeStoreCancellable() {
        storeCancellable = store.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    /// UI 状態をリセットし、次の文字起こし読み込みに備える。
    private func resetMeetingState() {
        saveNoteImmediately()
        meetingLoadTask?.cancel()
        store.clear()
        screenshots = []
        resetNoteState()
        resetSummaryState()
    }

    private func resetSummaryState() {
        currentMeetingSummary = nil
        currentMeetingActionItems = []
        lastSummaryURL = nil
        requestShowSummaryTab = false
        summaryError = nil
    }

    /// 現在の文字起こしコンテキスト（ID・プロジェクト情報）をセットする。
    private func setMeetingContext(
        id: UUID,
        dbQueue: DatabaseQueue,
        projectURL: URL?,
        projectId: UUID?,
        projectName: String?,
        vaultURL: URL
    ) {
        currentMeetingId = id
        currentProjectURL = projectURL
        currentProjectId = projectId
        currentProjectName = projectName
        currentVaultURL = vaultURL
        currentDbQueue = dbQueue
        resetSummaryState()
    }

    func updateCurrentProjectContext(projectURL: URL?, projectId: UUID?, projectName: String?) {
        currentProjectURL = projectURL
        currentProjectId = projectId
        currentProjectName = projectName
    }

    // MARK: - Analyzer Preparation

    func prepareAnalyzer() {
        isPreparingAnalyzer = true
        errorMessage = nil

        let localeIdentifier = selectedLocale
        let locale = Locale(identifier: localeIdentifier)

        Task {
            do {
                guard SpeechTranscriber.isAvailable else {
                    self.isPreparingAnalyzer = false
                    self.errorMessage = L10n.speechRecognitionUnavailable
                    return
                }

                // サポート言語一覧を取得
                let locales = await SpeechTranscriber.supportedLocales
                self.supportedLocales = locales.sortedByLocalizedName()
                self.updateFilteredLocales()

                // モデルのダウンロードと準備確認
                try await SpeechTranscriberService.ensureModelInstalled(locale: locale)
                self.analyzerReady = true
                self.isPreparingAnalyzer = false
            } catch {
                self.isPreparingAnalyzer = false
                self.errorMessage = L10n.speechPreparationFailed(error.localizedDescription)
                ErrorReportingService.capture(error, context: ["source": "prepareAnalyzer"])
            }
        }
    }

    /// SwiftUI の selection binding 更新後に副作用だけを適用する。
    func handleLocaleSelectionChange(from oldLocale: String, to newLocale: String) {
        applyLocaleChange(from: oldLocale, to: newLocale)
    }

    func handleMicrophoneSelectionChange(from oldID: AudioDeviceID?, to newID: AudioDeviceID?) {
        guard oldID != newID else { return }
        applyAudioSourceSelectionChange { self.selectedMicrophoneID = oldID }
    }

    func handleSystemAudioSelectionChange(from oldValue: Bool, to newValue: Bool) {
        guard oldValue != newValue else { return }
        applyAudioSourceSelectionChange { self.isSystemAudioEnabled = oldValue }
    }

    private func applyLocaleChange(from oldLocale: String, to newLocale: String) {
        guard newLocale != oldLocale || !analyzerReady else { return }
        AppSettings.shared.transcriptionLocale = newLocale

        if isListening {
            Task { await rebuildPipelines(reason: .localeChange) }
        } else {
            analyzerReady = false
            pipelines.removeAll()
            prepareAnalyzer()
        }
    }

    private func applyAudioSourceSelectionChange(restoreSelection: @escaping @MainActor () -> Void) {
        guard isListening else { return }

        Task { @MainActor in
            let applied = await rebuildPipelines(reason: .audioSourceChange)
            if !applied {
                restoreSelection()
            }
        }
    }

    private enum PipelineRebuildReason {
        case localeChange
        case audioSourceChange
    }

    @discardableResult
    private func rebuildPipelines(reason: PipelineRebuildReason) async -> Bool {
        await stopActivePipelines()
        stopActiveCaptures()

        let primaryLocale = Locale(identifier: selectedLocale)
        do {
            try await SpeechTranscriberService.ensureModelInstalled(locale: primaryLocale)
        } catch {
            setPipelineRebuildError(error, reason: reason)
            return false
        }

        var sourceErrors: [Error] = []

        if isMicEnabled {
            do {
                try await startMicrophonePipeline(locale: primaryLocale)
            } catch {
                sourceErrors.append(error)
            }
        }

        if isSystemAudioEnabled {
            do {
                try await startSystemAudioPipeline(locale: primaryLocale)
            } catch {
                sourceErrors.append(error)
            }
        }

        analyzerReady = true
        if let firstError = sourceErrors.first {
            setPipelineRebuildError(firstError, reason: reason)
            return false
        }

        errorMessage = nil
        return true
    }

    private func setPipelineRebuildError(_ error: Error, reason: PipelineRebuildReason) {
        switch reason {
        case .localeChange:
            errorMessage = L10n.languageChangeFailed(error.localizedDescription)
        case .audioSourceChange:
            errorMessage = error.localizedDescription
        }
    }

    private func stopActiveCaptures() {
        audioManager?.onAudioBuffer = nil
        audioManager?.stopCapture()
        audioManager = nil

        systemAudioManager?.onAudioBuffer = nil
        systemAudioManager?.onStreamStopped = nil
        systemAudioManager?.stopCapture()
        systemAudioManager = nil
    }

    private func stopActivePipelines() async {
        for pipeline in pipelines {
            pipeline.bridge.finish()
            await pipeline.service.stopStreaming()
        }
        pipelines.removeAll()
    }

    private func startMicrophonePipeline(locale: Locale) async throws {
        let hasMicPermission = await AudioCaptureManager.requestMicrophonePermission()
        guard hasMicPermission else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let (service, bridge, format) = try await buildPipeline(locale: locale, speakerLabel: "mic")
        try startMicrophoneCapture(
            bridge: bridge,
            targetFormat: format,
            selectedDeviceID: selectedMicrophoneID
        )
        pipelines.append((service: service, bridge: bridge))
    }

    private func startSystemAudioPipeline(locale: Locale) async throws {
        let (service, bridge, format) = try await buildPipeline(locale: locale, speakerLabel: "system")
        try await startSystemAudioCapture(bridge: bridge, targetFormat: format)
        pipelines.append((service: service, bridge: bridge))
    }

    // MARK: - Recording Control

    func toggleListening(
        dbQueue: DatabaseQueue,
        projectURL: URL?,
        vaultId: UUID,
        projectId: UUID?,
        projectName: String? = nil,
        vaultURL: URL
    ) {
        if isListening {
            stopListening()
        } else {
            Task {
                await startListening(
                    dbQueue: dbQueue,
                    projectURL: projectURL,
                    vaultId: vaultId,
                    projectId: projectId,
                    projectName: projectName,
                    vaultURL: vaultURL
                )
            }
        }
    }

    /// 新規文字起こしで録音を開始する。
    func startListening(
        dbQueue: DatabaseQueue,
        projectURL: URL?,
        vaultId: UUID,
        projectId: UUID?,
        projectName: String? = nil,
        vaultURL: URL,
        appendingTo existingMeetingId: UUID? = nil
    ) async {
        self.currentProjectURL = projectURL
        self.currentProjectId = projectId
        self.currentProjectName = projectName
        self.currentVaultURL = vaultURL
        self.currentDbQueue = dbQueue
        resetSummaryState()
        guard analyzerReady else {
            errorMessage = L10n.speechRecognitionNotReady
            return
        }

        guard hasEnabledAudioSource else {
            errorMessage = L10n.noAudioSourceSelected
            return
        }

        pipelines.removeAll()
        store.recordingStartTime = Date()

        if let existingMeetingId {
            // 追記モード: 既存セグメント ID を取得して PersistenceService に渡す
            let repo = MeetingRepository(dbQueue: dbQueue)
            let existingIds = (try? repo.fetchSegmentIds(forMeetingId: existingMeetingId)) ?? []
            persistenceService = MeetingPersistenceService(
                store: store,
                dbQueue: dbQueue,
                existingMeetingId: existingMeetingId,
                existingSegmentIds: existingIds
            )
            currentMeetingId = existingMeetingId
        } else {
            persistenceService = MeetingPersistenceService(
                store: store,
                dbQueue: dbQueue,
                vaultId: vaultId,
                projectId: projectId
            )
            currentMeetingId = persistenceService?.meetingId
        }

        do {
            let primaryLocale = Locale(identifier: selectedLocale)
            try await SpeechTranscriberService.ensureModelInstalled(locale: primaryLocale)

            if isMicEnabled {
                try await startMicrophonePipeline(locale: primaryLocale)
            }
            if isSystemAudioEnabled {
                try await startSystemAudioPipeline(locale: primaryLocale)
            }

            self.isListening = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            ErrorReportingService.capture(error, context: ["source": "startListening"])
            await stopActivePipelines()
            stopActiveCaptures()
        }
    }

    func stopListening() {
        stopActiveCaptures()
        isListening = false

        // ナビゲーション済みの場合、録音コンテキストからデータを取得
        let ctx = recordingContext
        let activeStore = ctx?.store ?? store
        let meetingId = ctx?.meetingId ?? currentMeetingId
        let projectName = ctx?.projectName ?? selectedProjectName
        let projectURL = ctx?.projectURL ?? currentProjectURL
        let vaultURL = ctx?.vaultURL ?? currentVaultURL
        let transcriptText = activeStore.exportForSummary()
        let recordingStart = activeStore.recordingStartTime ?? Date()
        let segments = activeStore.segments
        recordingContext = nil

        guard let vaultURL else { return }

        Task {
            await stopActivePipelines()
            persistenceService?.stop()
            persistenceService = nil

            if let meetingId, !segments.isEmpty {
                if AppSettings.shared.llmAutoSummaryEnabled {
                    // 要約 + ファイル書き出しを並行実行
                    await generateSummary(
                        meetingId: meetingId,
                        transcriptText: transcriptText,
                        projectURL: projectURL,
                        createdAt: recordingStart,
                        vaultURL: vaultURL,
                        projectName: projectName ?? "",
                        segments: segments
                    )
                } else {
                    // 要約なし: ファイル書き出しのみ
                    await exportFiles(
                        vaultURL: vaultURL,
                        meetingId: meetingId,
                        projectName: projectName ?? "",
                        createdAt: recordingStart,
                        segments: segments
                    )
                }
            }
        }
    }

    /// 現在選択中のプロジェクト名。
    private var selectedProjectName: String? {
        currentProjectName ?? currentProjectURL?.lastPathComponent
    }

    // MARK: - Agent

    /// 指定モードで Agent を起動する。初期メッセージを渡すとプロジェクトモードで即座に送信する。
    /// `workingDirectory` を渡すと `currentProjectURL` より優先して使用する。
    func startAgent(mode: AgentStartMode, initialMessage: String? = nil, workingDirectory: URL? = nil) {
        guard agentService == nil,
              let projectURL = workingDirectory ?? currentProjectURL else { return }
        let service = AgentService()
        self.agentService = service
        service.start(workingDirectory: projectURL, mode: mode, initialMessage: initialMessage)
    }

    /// Agent を明示的に停止する。
    func stopAgent() {
        agentService?.stop()
        agentService = nil
    }

    /// transcript 切替時に Agent のセグメント追跡をリセットする（transcript モードのみ）。
    func resetAgentSegmentTrackingIfNeeded() {
        guard let service = agentService, service.mode.isTranscript else { return }
        service.resetSegmentTracking(store: store)
    }

    // MARK: - Summary Generation

    /// 手動で要約を実行できるかどうか。
    var canGenerateSummary: Bool {
        guard currentMeetingId != nil,
              currentVaultURL != nil else { return false }
        return !store.segments.isEmpty
    }

    /// プルダウンメニューから手動で要約を実行する。
    func triggerManualSummary() {
        guard let meetingId = currentMeetingId,
              let vaultURL = currentVaultURL else { return }
        let projectURL = currentProjectURL
        let transcriptText = store.exportForSummary()
        let createdAt = store.recordingStartTime ?? Date()
        let projectName = selectedProjectName ?? ""
        let segments = store.segments
        requestShowSummaryTab = true
        Task {
            await generateSummary(
                meetingId: meetingId,
                transcriptText: transcriptText,
                projectURL: projectURL,
                createdAt: createdAt,
                vaultURL: vaultURL,
                projectName: projectName,
                segments: segments
            )
        }
    }

    func generateSummary(
        meetingId: UUID,
        transcriptText: String,
        projectURL: URL?,
        createdAt: Date,
        vaultURL: URL,
        projectName: String,
        segments: [TranscriptSegment]
    ) async {
        guard !transcriptText.isEmpty else { return }

        guard AppSettings.shared.isLLMConfigComplete else {
            summaryError = L10n.llmConfigIncomplete
            return
        }

        // 要約前にノートを即座に保存してから取得
        saveNoteImmediately()
        let currentNoteText = noteText

        summaryGeneratingMeetingId = meetingId
        summaryError = nil
        lastSummaryURL = nil
        summaryProgress.show()

        do {
            let dbQueue = currentDbQueue
            var screenshots: [MeetingScreenshotRecord] = []
            if let queue = dbQueue {
                let repo = MeetingRepository(dbQueue: queue)
                screenshots = (try? repo.fetchScreenshots(forMeetingId: meetingId)) ?? []
            }

            let screenshotsForExport = screenshots

            // Screenshots の書き出し
            summaryProgress.screenshotExport = screenshots.isEmpty ? nil : .running

            // Transcript の書き出し
            summaryProgress.transcriptExport = .running

            // LLM 要約
            summaryProgress.summaryGeneration = .running

            // LLM 要約とファイル書き出しを並行実行
            async let summaryResult = SummaryService.generateSummary(
                projectURL: projectURL,
                vaultURL: vaultURL,
                meetingId: meetingId,
                createdAt: createdAt,
                transcriptText: transcriptText,
                noteText: currentNoteText.isEmpty ? nil : currentNoteText,
                screenshots: screenshots
            )

            async let fileExport: Void = exportTranscriptAndScreenshotsWithProgress(
                vaultURL: vaultURL,
                meetingId: meetingId,
                projectName: projectName,
                createdAt: createdAt,
                segments: segments,
                screenshots: screenshotsForExport
            )

            let generatedSummary = try await summaryResult
            summaryProgress.summaryGeneration = .completed

            _ = await fileExport
            if let dbQueue {
                let repo = MeetingRepository(dbQueue: dbQueue)
                try repo.applyGeneratedSummary(
                    toMeetingId: meetingId,
                    title: generatedSummary.title,
                    summary: generatedSummary.summary,
                    tags: generatedSummary.tags,
                    actionItems: generatedSummary.actionItems
                )
            }
            if currentMeetingId == meetingId {
                currentMeetingSummary = generatedSummary.summary
                lastSummaryURL = generatedSummary.fileURL
                if let dbQueue {
                    let repo = MeetingRepository(dbQueue: dbQueue)
                    currentMeetingActionItems = (try? repo.fetchActionItems(forMeetingId: meetingId)) ?? []
                } else {
                    currentMeetingActionItems = []
                }
            }
        } catch {
            if currentMeetingId == meetingId {
                summaryError = error.localizedDescription
                requestShowSummaryTab = false
            }
            summaryProgress.summaryGeneration = .failed(error.localizedDescription)
            ErrorReportingService.capture(error, context: ["source": "summaryGeneration"])
        }

        if summaryGeneratingMeetingId == meetingId {
            summaryGeneratingMeetingId = nil
        }

        // 全完了後に自動で非表示
        if summaryProgress.isAllDone {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) {
                summaryProgress.dismiss()
            }
        }
    }

    /// 要約なしでファイル書き出しのみ実行する。
    private func exportFiles(
        vaultURL: URL,
        meetingId: UUID,
        projectName: String,
        createdAt: Date,
        segments: [TranscriptSegment]
    ) async {
        var screenshots: [MeetingScreenshotRecord] = []
        if let dbQueue = currentDbQueue {
            let repo = MeetingRepository(dbQueue: dbQueue)
            screenshots = (try? repo.fetchScreenshots(forMeetingId: meetingId)) ?? []
        }
        await exportTranscriptAndScreenshots(
            vaultURL: vaultURL,
            meetingId: meetingId,
            projectName: projectName,
            createdAt: createdAt,
            segments: segments,
            screenshots: screenshots
        )
    }

    /// transcript と screenshot をファイルに書き出す共通処理。メインアクター外で実行。
    private func exportTranscriptAndScreenshots(
        vaultURL: URL,
        meetingId: UUID,
        projectName: String,
        createdAt: Date,
        segments: [TranscriptSegment],
        screenshots: [MeetingScreenshotRecord]
    ) async {
        async let transcriptPath = Task.detached {
            try? TranscriptExportService.exportTranscript(
                vaultURL: vaultURL,
                meetingId: meetingId,
                projectName: projectName,
                createdAt: createdAt,
                segments: segments
            )
        }.value

        async let screenshotExport: Void = Task.detached {
            guard !screenshots.isEmpty else { return }
            _ = try? ScreenshotExportService.exportScreenshots(
                vaultURL: vaultURL,
                screenshots: screenshots
            )
        }.value

        _ = await transcriptPath
        _ = await screenshotExport
    }

    /// transcript と screenshot をファイルに書き出し、進捗トーストを更新する。
    private func exportTranscriptAndScreenshotsWithProgress(
        vaultURL: URL,
        meetingId: UUID,
        projectName: String,
        createdAt: Date,
        segments: [TranscriptSegment],
        screenshots: [MeetingScreenshotRecord]
    ) async {
        async let transcriptPath = Task.detached {
            try? TranscriptExportService.exportTranscript(
                vaultURL: vaultURL,
                meetingId: meetingId,
                projectName: projectName,
                createdAt: createdAt,
                segments: segments
            )
        }.value

        async let screenshotExport: Void = Task.detached {
            guard !screenshots.isEmpty else { return }
            _ = try? ScreenshotExportService.exportScreenshots(
                vaultURL: vaultURL,
                screenshots: screenshots
            )
        }.value

        _ = await transcriptPath
        summaryProgress.transcriptExport = .completed

        _ = await screenshotExport
        if !screenshots.isEmpty {
            summaryProgress.screenshotExport = .completed
        }
    }

    func clearText() {
        store.clear()
        persistenceService?.reset()
        Task {
            for pipeline in pipelines {
                await pipeline.service.reset()
            }
        }
    }

    // MARK: - Screenshot

    /// キャプチャ対象のウィンドウ一覧を更新する。
    func refreshAvailableWindows() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let myBundleID = Bundle.main.bundleIdentifier
                self.availableWindows = content.windows
                    .filter { window in
                        window.isOnScreen
                            && window.frame.width > 0
                            && window.frame.height > 0
                            && window.windowLayer == 0
                            && !(window.title ?? "").isEmpty
                            && window.owningApplication?.bundleIdentifier != myBundleID
                    }
                    .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
                // 選択中のウィンドウが一覧から消えていたらリセット
                if let id = selectedWindowID,
                   !self.availableWindows.contains(where: { $0.windowID == id }) {
                    selectedWindowID = nil
                }
            } catch {
                self.availableWindows = []
            }
        }
    }

    func takeScreenshot() {
        guard let meetingId = activeMeetingIdForSessionControls,
              let dbQueue = activeDbQueueForSessionControls else { return }

        let shouldRefreshVisibleScreenshots = currentMeetingId == meetingId

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                let filter: SCContentFilter
                let config = SCScreenshotConfiguration()
                config.showsCursor = false
                config.dynamicRange = .sdr

                if let windowID = selectedWindowID,
                   let window = content.windows.first(where: { $0.windowID == windowID }) {
                    // 選択ウィンドウをキャプチャ
                    filter = SCContentFilter(desktopIndependentWindow: window)
                } else {
                    // デスクトップ全体をキャプチャ
                    guard let display = content.displays.first else {
                        errorMessage = "ディスプレイが見つかりません"
                        return
                    }
                    filter = SCContentFilter(display: display, excludingWindows: [])
                }

                // 対象の実サイズに合わせて ScreenCaptureKit に出力サイズを決めさせる。
                // `window.frame * 2` のような固定スケールは、非 Retina の拡張モニタで余白を生む。
                let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
                guard let cgImage = output.sdrImage else {
                    throw ScreenshotError.imageUnavailable
                }

                // 画像エンコードを MainActor 外で実行（WebP → JPEG フォールバック）
                let imageData: Data = try await Task.detached(priority: .userInitiated) {
                    guard let encoded = ImageEncoder.encode(cgImage, quality: 0.70) else {
                        throw ScreenshotError.encodingFailed
                    }
                    return encoded
                }.value

                let record = MeetingScreenshotRecord(
                    id: UUID.v7(),
                    meetingId: meetingId,
                    capturedAt: Date(),
                    imageData: imageData,
                    mimeType: ImageEncoder.preferredMIMEType
                )

                try await dbQueue.write { db in
                    try record.insert(db)
                }
                if shouldRefreshVisibleScreenshots {
                    reloadScreenshots()
                }
            } catch {
                errorMessage = "スクリーンショットの取得に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Note Auto-Save

    private func setupNoteAutoSave() {
        noteAutoSaveCancellable?.cancel()
        noteAutoSaveCancellable = $noteText
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.saveNote(text: text)
            }
    }

    private func resetNoteState() {
        noteText = ""
        hasNote = false
        currentNoteCreatedAt = nil
        lastSavedNoteText = nil
        noteAutoSaveCancellable?.cancel()
    }

    private func saveNote(text: String) {
        guard let meetingId = currentMeetingId,
              let dbQueue = currentDbQueue else { return }
        let now = Date()
        let isNew = !hasNote
        let note = MeetingNoteRecord(
            meetingId: meetingId,
            text: text,
            createdAt: isNew ? now : (currentNoteCreatedAt ?? now),
            updatedAt: now
        )
        let repo = MeetingRepository(dbQueue: dbQueue)
        do {
            try repo.upsertNote(note)
            if isNew {
                hasNote = true
                currentNoteCreatedAt = now
            }
            lastSavedNoteText = text
        } catch {
            Logger(subsystem: "com.dahlia", category: "CaptionViewModel")
                .error("Failed to save note: \(error)")
        }
    }

    private func saveNoteImmediately() {
        guard hasNote || !noteText.isEmpty,
              noteText != lastSavedNoteText else { return }
        saveNote(text: noteText)
    }

    /// DB からスクリーンショット一覧を再読み込みする。
    func reloadScreenshots() {
        guard let meetingId = currentMeetingId,
              let dbQueue = currentDbQueue else {
            screenshots = []
            return
        }
        let repo = MeetingRepository(dbQueue: dbQueue)
        screenshots = (try? repo.fetchScreenshots(forMeetingId: meetingId)) ?? []
    }

    func deleteScreenshot(_ screenshot: MeetingScreenshotRecord) {
        guard let dbQueue = activeDbQueueForSessionControls else { return }
        let repo = MeetingRepository(dbQueue: dbQueue)
        try? repo.deleteScreenshot(id: screenshot.id)
        if currentMeetingId == screenshot.meetingId {
            reloadScreenshots()
        }
    }

    func toggleActionItemCompletion(_ actionItem: ActionItemRecord) {
        setActionItemCompleted(actionItem, isCompleted: !actionItem.isCompleted)
    }

    func setActionItemCompleted(_ actionItem: ActionItemRecord, isCompleted: Bool) {
        guard let dbQueue = currentDbQueue,
              let index = currentMeetingActionItems.firstIndex(where: { $0.id == actionItem.id }) else { return }

        let previousValue = currentMeetingActionItems[index].isCompleted
        currentMeetingActionItems[index].isCompleted = isCompleted

        let repo = MeetingRepository(dbQueue: dbQueue)
        do {
            try repo.setActionItemCompleted(id: actionItem.id, isCompleted: isCompleted)
        } catch {
            currentMeetingActionItems[index].isCompleted = previousValue
            summaryError = L10n.actionItemUpdateFailed(error.localizedDescription)
            Logger(subsystem: "com.dahlia", category: "CaptionViewModel")
                .error("Failed to update action item completion: \(error)")
        }
    }

    func deleteActionItem(_ actionItem: ActionItemRecord) {
        guard let dbQueue = currentDbQueue,
              let index = currentMeetingActionItems.firstIndex(where: { $0.id == actionItem.id }) else { return }

        let removedActionItem = currentMeetingActionItems.remove(at: index)
        let repo = MeetingRepository(dbQueue: dbQueue)

        do {
            try repo.deleteActionItem(id: actionItem.id)
        } catch {
            currentMeetingActionItems.insert(removedActionItem, at: index)
            summaryError = L10n.actionItemDeleteFailed(error.localizedDescription)
            Logger(subsystem: "com.dahlia", category: "CaptionViewModel")
                .error("Failed to delete action item: \(error)")
        }
    }

    func toggleActionItemAssignedToMe(_ actionItem: ActionItemRecord) {
        setActionItemAssignee(actionItem, assignee: actionItem.isExplicitlyAssignedToMe ? "" : SummaryActionItem.selfAssigneeKey)
    }

    func setActionItemAssignee(_ actionItem: ActionItemRecord, assignee: String) {
        guard let dbQueue = currentDbQueue,
              let index = currentMeetingActionItems.firstIndex(where: { $0.id == actionItem.id }) else { return }

        let normalizedAssignee = SummaryActionItem.normalize(assignee)
        let previousAssignee = currentMeetingActionItems[index].assignee
        currentMeetingActionItems[index].assignee = normalizedAssignee

        let repo = MeetingRepository(dbQueue: dbQueue)
        do {
            try repo.setActionItemAssignee(id: actionItem.id, assignee: normalizedAssignee)
        } catch {
            currentMeetingActionItems[index].assignee = previousAssignee
            summaryError = L10n.actionItemAssigneeUpdateFailed(error.localizedDescription)
            Logger(subsystem: "com.dahlia", category: "CaptionViewModel")
                .error("Failed to update action item assignee: \(error)")
        }
    }

    func exportTranscript() {
        let text = store.exportAsText()
        guard !text.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript_\(Self.fileDateFormatter.string(from: store.recordingStartTime ?? Date())).txt"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Pipeline Construction

    private func buildPipeline(
        locale: Locale,
        speakerLabel: String
    ) async throws -> (service: SpeechTranscriberService, bridge: AudioBufferBridge, format: AVAudioFormat) {
        let service = SpeechTranscriberService(locale: locale, speakerLabel: speakerLabel)
        try await service.prepare()
        guard let format = await service.targetAudioFormat() else {
            throw AudioCaptureError.converterCreationFailed
        }
        let bridge = AudioBufferBridge(sampleRate: format.sampleRate)
        try await service.startStreaming(store: store, bridge: bridge)
        return (service: service, bridge: bridge, format: format)
    }

    // MARK: - Private Helpers

    private func startMicrophoneCapture(
        bridge: AudioBufferBridge,
        targetFormat: AVAudioFormat,
        selectedDeviceID: AudioDeviceID?
    ) throws {
        let manager = AudioCaptureManager()
        manager.onAudioBuffer = { [bridge] buffer in
            bridge.appendBuffer(buffer)
        }
        try manager.startCapture(targetFormat: targetFormat, selectedDeviceID: selectedDeviceID)
        self.audioManager = manager
    }

    private func startSystemAudioCapture(bridge: AudioBufferBridge, targetFormat: AVAudioFormat) async throws {
        let hasPermission = await SystemAudioCaptureManager.requestPermission()
        guard hasPermission else {
            throw SystemAudioCaptureError.screenRecordingPermissionDenied
        }

        let manager = SystemAudioCaptureManager()
        manager.onAudioBuffer = { [bridge] buffer in
            bridge.appendBuffer(buffer)
        }
        manager.onStreamStopped = { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error?.localizedDescription ?? L10n.systemAudioCaptureStopped
                if self?.audioManager == nil {
                    self?.isListening = false
                }
            }
        }
        try await manager.startCapture(targetFormat: targetFormat)
        self.systemAudioManager = manager
    }
}
