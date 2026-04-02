import SwiftUI
import Combine
import Speech
import GRDB

/// 音声キャプチャ → Speech フレームワーク文字起こし → UI 更新を統括するビューモデル。
@MainActor
final class CaptionViewModel: ObservableObject {
    // MARK: - Published State

    @Published var store = TranscriptStore()
    @Published var isListening: Bool = false
    @Published var analyzerReady: Bool = false
    @Published var isPreparingAnalyzer: Bool = false
    @Published var errorMessage: String?
    @Published var audioSourceMode: AudioSourceMode = .both
    @Published var selectedLocale: String = AppSettings.shared.transcriptionLocale
    @Published var supportedLocales: [Locale] = []
    @Published var filteredLocales: [Locale] = []

    // MARK: - Transcription State

    var currentTranscriptionId: UUID?

    /// 録音中でなく、文字起こしを表示中の場合 true。
    var isViewingHistory: Bool {
        !isListening && currentTranscriptionId != nil
    }

    /// マイクが有効か（audioSourceMode から導出）。
    var isMicEnabled: Bool { audioSourceMode == .microphone || audioSourceMode == .both }

    /// システム音声が有効か（audioSourceMode から導出）。
    var isSystemAudioEnabled: Bool { audioSourceMode == .systemAudio || audioSourceMode == .both }

    // MARK: - Private

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
            .publisher(for: \.enabledLocaleIdentifiersJSON)
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
    func loadTranscription(_ transcriptionId: UUID, dbQueue: DatabaseQueue) {
        guard !isListening else { return }
        currentTranscriptionId = transcriptionId

        let repo = TranscriptionRepository(dbQueue: dbQueue)
        let records = (try? repo.fetchSegments(forTranscriptionId: transcriptionId)) ?? []
        let segments = records.map { TranscriptSegment(from: $0) }
        store.loadSegments(segments)
    }

    /// 現在の文字起こし表示をクリアして初期状態に戻す。
    func clearCurrentTranscription() {
        currentTranscriptionId = nil
        store.clear()
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

    func toggleListening(dbQueue: DatabaseQueue) {
        if isListening {
            stopListening()
        } else {
            Task { await startListening(dbQueue: dbQueue) }
        }
    }

    /// 新規文字起こしで録音を開始する。
    func startListening(dbQueue: DatabaseQueue, appendingTo existingTranscriptionId: UUID? = nil) async {
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
                existingTranscriptionId: existingTranscriptionId,
                existingSegmentIds: existingIds
            )
            currentTranscriptionId = existingTranscriptionId
        } else {
            persistenceService = TranscriptPersistenceService(
                store: store,
                dbQueue: dbQueue
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

        Task {
            for pipeline in pipelines {
                pipeline.bridge.finish()
                await pipeline.service.stopStreaming()
            }
            pipelines.removeAll()
            persistenceService?.stop()
            persistenceService = nil
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
