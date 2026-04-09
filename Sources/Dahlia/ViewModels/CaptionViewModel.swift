import Combine
import GRDB
@preconcurrency import ScreenCaptureKit
import Speech
import SwiftUI

private enum ScreenshotError: Error {
    case encodingFailed
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
    @Published var audioSourceMode: AudioSourceMode = .both
    @Published var selectedLocale: String = AppSettings.shared.transcriptionLocale
    @Published var supportedLocales: [Locale] = []
    @Published var filteredLocales: [Locale] = []

    // MARK: - Transcription State

    var currentTranscriptionId: UUID?
    var currentProjectURL: URL?
    var currentProjectId: UUID?
    var currentProjectName: String?
    var currentVaultURL: URL?

    // MARK: - Summary State

    @Published var isSummaryGenerating = false
    @Published var summaryError: String?
    @Published var lastSummaryURL: URL?
    /// Summary タブへの切り替えをリクエストするフラグ。
    @Published var requestShowSummaryTab = false

    // MARK: - Screenshot State

    @Published var screenshots: [ScreenshotRecord] = []
    /// キャプチャ対象として選択可能なウィンドウ一覧。
    @Published var availableWindows: [SCWindow] = []
    /// 選択中のウィンドウ ID。nil の場合はデスクトップ全体をキャプチャ。
    @Published var selectedWindowID: CGWindowID?

    /// 録音中でなく、文字起こしを表示中の場合 true。
    var isViewingHistory: Bool {
        !isListening && currentTranscriptionId != nil
    }

    /// マイクが有効か（audioSourceMode から導出）。
    var isMicEnabled: Bool { audioSourceMode == .microphone || audioSourceMode == .both }

    /// システム音声が有効か（audioSourceMode から導出）。
    var isSystemAudioEnabled: Bool { audioSourceMode == .systemAudio || audioSourceMode == .both }

    // MARK: - Private

    private var currentDbQueue: DatabaseQueue?
    private var audioManager: AudioCaptureManager?
    private var systemAudioManager: SystemAudioCaptureManager?
    private var pipelines: [(service: SpeechTranscriberService, bridge: AudioBufferBridge)] = []
    private var persistenceService: TranscriptPersistenceService?
    private var storeCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?

    init() {
        storeCancellable = store.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

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

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    // MARK: - Transcription Loading

    /// DB から文字起こしのセグメントを読み込んで表示する。
    func loadTranscription(_ transcriptionId: UUID, dbQueue: DatabaseQueue, projectURL: URL, projectId: UUID, projectName: String? = nil, vaultURL: URL) {
        guard !isListening else { return }
        currentTranscriptionId = transcriptionId
        currentProjectURL = projectURL
        currentProjectId = projectId
        currentProjectName = projectName
        currentVaultURL = vaultURL
        currentDbQueue = dbQueue

        let repo = TranscriptionRepository(dbQueue: dbQueue)
        let detail = try? repo.fetchTranscriptionDetail(id: transcriptionId)
        let segments = (detail?.segments ?? []).map { TranscriptSegment(from: $0) }
        store.loadSegments(segments)
        screenshots = detail?.screenshots ?? []

        // summaryCreated フラグが立っている場合のみファイルを探索
        if let transcription = detail?.transcription, transcription.summaryCreated {
            lastSummaryURL = SummaryService.findSummaryFile(in: projectURL, transcriptionId: transcriptionId)
        } else {
            lastSummaryURL = nil
        }
        summaryError = nil
    }

    /// 現在の文字起こし表示をクリアして初期状態に戻す。
    func clearCurrentTranscription() {
        currentTranscriptionId = nil
        currentProjectURL = nil
        currentProjectId = nil
        currentProjectName = nil
        currentVaultURL = nil
        store.clear()
        lastSummaryURL = nil
        summaryError = nil
        screenshots = []
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
            }
        }
    }

    /// マイク側の認識言語を変更する。
    /// 録音中の場合はオーディオキャプチャを維持したまま Speech サービスだけ差し替える。
    func changeLocale(_ newLocale: String) {
        guard newLocale != selectedLocale || !analyzerReady else { return }
        selectedLocale = newLocale
        AppSettings.shared.transcriptionLocale = newLocale

        if isListening {
            Task { await rebuildPipelines() }
        } else {
            analyzerReady = false
            pipelines.removeAll()
            prepareAnalyzer()
        }
    }

    /// 録音中にパイプラインを再構築する。オーディオキャプチャは維持し、Speech サービスのみ差し替え。
    private func rebuildPipelines() async {
        // 1. 全パイプラインを停止（オーディオキャプチャは維持）
        for pipeline in pipelines {
            pipeline.bridge.finish()
            await pipeline.service.stopStreaming()
        }
        pipelines.removeAll()

        // 2. 新しいパイプラインを構築
        let primaryLocale = Locale(identifier: selectedLocale)

        do {
            try await SpeechTranscriberService.ensureModelInstalled(locale: primaryLocale)

            if isMicEnabled {
                let (service, bridge, _) = try await buildPipeline(locale: primaryLocale, speakerLabel: "mic")
                audioManager?.onAudioBuffer = { [bridge] buffer in bridge.appendBuffer(buffer) }
                pipelines.append((service: service, bridge: bridge))
            }
            if isSystemAudioEnabled {
                let (service, bridge, _) = try await buildPipeline(locale: primaryLocale, speakerLabel: "system")
                systemAudioManager?.onAudioBuffer = { [bridge] buffer in bridge.appendBuffer(buffer) }
                pipelines.append((service: service, bridge: bridge))
            }

            self.analyzerReady = true
            errorMessage = nil
        } catch {
            errorMessage = L10n.languageChangeFailed(error.localizedDescription)
        }
    }

    // MARK: - Recording Control

    func toggleListening(dbQueue: DatabaseQueue, projectURL: URL, projectId: UUID, projectName: String? = nil, vaultURL: URL) {
        if isListening {
            stopListening()
        } else {
            Task { await startListening(dbQueue: dbQueue, projectURL: projectURL, projectId: projectId, projectName: projectName, vaultURL: vaultURL) }
        }
    }

    /// 新規文字起こしで録音を開始する。
    func startListening(
        dbQueue: DatabaseQueue,
        projectURL: URL,
        projectId: UUID,
        projectName: String? = nil,
        vaultURL: URL,
        appendingTo existingTranscriptionId: UUID? = nil
    ) async {
        self.currentProjectURL = projectURL
        self.currentProjectId = projectId
        self.currentProjectName = projectName
        self.currentVaultURL = vaultURL
        self.currentDbQueue = dbQueue
        guard analyzerReady else {
            errorMessage = L10n.speechRecognitionNotReady
            return
        }

        pipelines.removeAll()
        store.recordingStartTime = Date()

        if let existingTranscriptionId {
            // 追記モード: 既存セグメント ID を取得して PersistenceService に渡す
            let repo = TranscriptionRepository(dbQueue: dbQueue)
            let existingIds = (try? repo.fetchSegmentIds(forTranscriptionId: existingTranscriptionId)) ?? []
            persistenceService = TranscriptPersistenceService(
                store: store,
                dbQueue: dbQueue,
                projectId: projectId,
                existingTranscriptionId: existingTranscriptionId,
                existingSegmentIds: existingIds
            )
            currentTranscriptionId = existingTranscriptionId
        } else {
            persistenceService = TranscriptPersistenceService(
                store: store,
                dbQueue: dbQueue,
                projectId: projectId
            )
            currentTranscriptionId = persistenceService?.transcriptionId
        }

        do {
            // マイクが有効な場合のみ権限を要求
            if isMicEnabled {
                let hasMicPermission = await AudioCaptureManager.requestMicrophonePermission()
                guard hasMicPermission else {
                    throw AudioCaptureError.microphonePermissionDenied
                }
            }

            let primaryLocale = Locale(identifier: selectedLocale)
            try await SpeechTranscriberService.ensureModelInstalled(locale: primaryLocale)

            if isMicEnabled {
                let (service, bridge, format) = try await buildPipeline(locale: primaryLocale, speakerLabel: "mic")
                try startMicrophoneCapture(bridge: bridge, targetFormat: format)
                pipelines.append((service: service, bridge: bridge))
            }
            if isSystemAudioEnabled {
                let (service, bridge, format) = try await buildPipeline(locale: primaryLocale, speakerLabel: "system")
                try await startSystemAudioCapture(bridge: bridge, targetFormat: format)
                pipelines.append((service: service, bridge: bridge))
            }

            self.isListening = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            audioManager?.stopCapture()
            audioManager = nil
            systemAudioManager?.stopCapture()
            systemAudioManager = nil
            pipelines.removeAll()
        }
    }

    func stopListening() {
        audioManager?.stopCapture()
        audioManager = nil
        systemAudioManager?.stopCapture()
        systemAudioManager = nil
        isListening = false

        let transcriptionId = currentTranscriptionId
        let projectName = selectedProjectName
        let transcriptText = store.exportForSummary()
        let projectURL = currentProjectURL
        let recordingStart = store.recordingStartTime ?? Date()
        let segments = store.segments
        guard let vaultURL = currentVaultURL else { return }

        Task {
            for pipeline in pipelines {
                pipeline.bridge.finish()
                await pipeline.service.stopStreaming()
            }
            pipelines.removeAll()
            persistenceService?.stop()
            persistenceService = nil

            if let transcriptionId, !segments.isEmpty {
                if AppSettings.shared.llmAutoSummaryEnabled, let projectURL {
                    // 要約 + ファイル書き出しを並行実行
                    await generateSummary(
                        transcriptionId: transcriptionId,
                        transcriptText: transcriptText,
                        projectURL: projectURL,
                        startedAt: recordingStart,
                        vaultURL: vaultURL,
                        projectName: projectName ?? "",
                        segments: segments
                    )
                } else {
                    // 要約なし: ファイル書き出しのみ
                    await exportFiles(
                        vaultURL: vaultURL,
                        transcriptionId: transcriptionId,
                        projectName: projectName ?? "",
                        startedAt: recordingStart,
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

    // MARK: - Summary Generation

    /// 手動で要約を実行できるかどうか。
    var canGenerateSummary: Bool {
        guard currentTranscriptionId != nil,
              currentProjectURL != nil else { return false }
        return !store.segments.isEmpty
    }

    /// プルダウンメニューから手動で要約を実行する。
    func triggerManualSummary() {
        guard let transcriptionId = currentTranscriptionId,
              let projectURL = currentProjectURL,
              let vaultURL = currentVaultURL else { return }
        let transcriptText = store.exportForSummary()
        let startedAt = store.recordingStartTime ?? Date()
        let projectName = selectedProjectName ?? ""
        let segments = store.segments
        requestShowSummaryTab = true
        Task {
            await generateSummary(
                transcriptionId: transcriptionId,
                transcriptText: transcriptText,
                projectURL: projectURL,
                startedAt: startedAt,
                vaultURL: vaultURL,
                projectName: projectName,
                segments: segments
            )
        }
    }

    func generateSummary(
        transcriptionId: UUID,
        transcriptText: String,
        projectURL: URL,
        startedAt: Date,
        vaultURL: URL,
        projectName: String,
        segments: [TranscriptSegment]
    ) async {
        guard !transcriptText.isEmpty else { return }

        guard AppSettings.shared.isLLMConfigComplete else {
            summaryError = L10n.llmConfigIncomplete
            return
        }

        isSummaryGenerating = true
        summaryError = nil
        lastSummaryURL = nil

        do {
            var screenshots: [ScreenshotRecord] = []
            if let queue = currentDbQueue {
                let repo = TranscriptionRepository(dbQueue: queue)
                screenshots = (try? repo.fetchScreenshots(forTranscriptionId: transcriptionId)) ?? []
            }

            let screenshotsForExport = screenshots

            // LLM 要約とファイル書き出しを並行実行
            async let summaryResult = SummaryService.generateSummary(
                projectURL: projectURL,
                transcriptionId: transcriptionId,
                startedAt: startedAt,
                transcriptText: transcriptText,
                screenshots: screenshots
            )

            async let fileExport: Void = exportTranscriptAndScreenshots(
                vaultURL: vaultURL,
                transcriptionId: transcriptionId,
                projectName: projectName,
                startedAt: startedAt,
                segments: segments,
                screenshots: screenshotsForExport
            )

            let fileURL = try await summaryResult
            _ = await fileExport
            lastSummaryURL = fileURL

            // summaryCreated フラグを立てる
            if let dbQueue = currentDbQueue {
                let repo = TranscriptionRepository(dbQueue: dbQueue)
                try? repo.markSummaryCreated(id: transcriptionId)
            }
        } catch {
            summaryError = error.localizedDescription
        }

        isSummaryGenerating = false
    }

    /// 要約なしでファイル書き出しのみ実行する。
    private func exportFiles(
        vaultURL: URL,
        transcriptionId: UUID,
        projectName: String,
        startedAt: Date,
        segments: [TranscriptSegment]
    ) async {
        var screenshots: [ScreenshotRecord] = []
        if let dbQueue = currentDbQueue {
            let repo = TranscriptionRepository(dbQueue: dbQueue)
            screenshots = (try? repo.fetchScreenshots(forTranscriptionId: transcriptionId)) ?? []
        }
        await exportTranscriptAndScreenshots(
            vaultURL: vaultURL,
            transcriptionId: transcriptionId,
            projectName: projectName,
            startedAt: startedAt,
            segments: segments,
            screenshots: screenshots
        )
    }

    /// transcript と screenshot をファイルに書き出す共通処理。メインアクター外で実行。
    private func exportTranscriptAndScreenshots(
        vaultURL: URL,
        transcriptionId: UUID,
        projectName: String,
        startedAt: Date,
        segments: [TranscriptSegment],
        screenshots: [ScreenshotRecord]
    ) async {
        let dbQueue = currentDbQueue

        async let transcriptPath = Task.detached {
            try? TranscriptExportService.exportTranscript(
                vaultURL: vaultURL,
                transcriptionId: transcriptionId,
                projectName: projectName,
                startedAt: startedAt,
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

        if let path = await transcriptPath, let dbQueue {
            let repo = TranscriptionRepository(dbQueue: dbQueue)
            try? repo.updateTranscriptFilePath(id: transcriptionId, path: path)
        }
        _ = await screenshotExport
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
        guard let transcriptionId = currentTranscriptionId,
              let dbQueue = currentDbQueue else { return }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                let filter: SCContentFilter
                let config = SCStreamConfiguration()
                config.showsCursor = false

                if let windowID = selectedWindowID,
                   let window = content.windows.first(where: { $0.windowID == windowID }) {
                    // 選択ウィンドウをキャプチャ
                    filter = SCContentFilter(desktopIndependentWindow: window)
                    config.width = Int(window.frame.width) * 2
                    config.height = Int(window.frame.height) * 2
                } else {
                    // デスクトップ全体をキャプチャ
                    guard let display = content.displays.first else {
                        errorMessage = "ディスプレイが見つかりません"
                        return
                    }
                    filter = SCContentFilter(display: display, excludingWindows: [])
                    config.width = display.width * 2
                    config.height = display.height * 2
                }

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                // 画像エンコードを MainActor 外で実行（WebP → JPEG フォールバック）
                let imageData: Data = try await Task.detached(priority: .userInitiated) {
                    guard let encoded = ImageEncoder.encode(cgImage, quality: 0.70) else {
                        throw ScreenshotError.encodingFailed
                    }
                    return encoded
                }.value

                let record = ScreenshotRecord(
                    id: UUID.v7(),
                    transcriptionId: transcriptionId,
                    capturedAt: Date(),
                    imageData: imageData
                )

                try await dbQueue.write { db in
                    try record.insert(db)
                }
                reloadScreenshots()
            } catch {
                errorMessage = "スクリーンショットの取得に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    /// DB からスクリーンショット一覧を再読み込みする。
    func reloadScreenshots() {
        guard let transcriptionId = currentTranscriptionId,
              let dbQueue = currentDbQueue else {
            screenshots = []
            return
        }
        let repo = TranscriptionRepository(dbQueue: dbQueue)
        screenshots = (try? repo.fetchScreenshots(forTranscriptionId: transcriptionId)) ?? []
    }

    func deleteScreenshot(_ screenshot: ScreenshotRecord) {
        guard let dbQueue = currentDbQueue else { return }
        let repo = TranscriptionRepository(dbQueue: dbQueue)
        try? repo.deleteScreenshot(id: screenshot.id)
        reloadScreenshots()
    }

    func exportTranscript() {
        let text = store.exportAsText()
        guard !text.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript_\(Self.fileDateFormatter.string(from: Date())).txt"

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

    private func startMicrophoneCapture(bridge: AudioBufferBridge, targetFormat: AVAudioFormat) throws {
        let manager = AudioCaptureManager()
        manager.onAudioBuffer = { [bridge] buffer in
            bridge.appendBuffer(buffer)
        }
        try manager.startCapture(targetFormat: targetFormat)
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
            DispatchQueue.main.async {
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
