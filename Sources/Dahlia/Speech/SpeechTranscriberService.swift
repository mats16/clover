import AVFoundation
import CoreMedia
import Speech

/// SpeechAnalyzer + SpeechTranscriber によるストリーミング文字起こしサービス。
/// AudioBufferBridge から受け取った AsyncStream<AnalyzerInput> を SpeechAnalyzer に渡し、
/// SpeechTranscriber の結果を TranscriptStore に反映する。
actor SpeechTranscriberService {
    private nonisolated static let ignoredConfirmedTexts: Set<String> = [".", "あ"]

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var resultTask: Task<Void, Never>?
    private var bestFormat: AVAudioFormat?

    private let locale: Locale
    private let speakerLabel: String?

    init(locale: Locale = Locale(identifier: "ja-JP"), speakerLabel: String? = nil) {
        self.locale = locale
        self.speakerLabel = speakerLabel
    }

    nonisolated static func normalizedTranscriptText(_ rawText: String) -> String? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard !ignoredConfirmedTexts.contains(text) else { return nil }
        return text
    }

    /// 指定ロケールのモデルがインストール済みか確認し、未インストールならダウンロードする。
    /// 複数パイプライン作成前に一度だけ呼ぶことで二重ダウンロードを回避する。
    static func ensureModelInstalled(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        let status = await AssetInventory.status(forModules: [transcriber])
        if status < .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
    }

    /// SpeechTranscriber と SpeechAnalyzer を初期化し、最適なオーディオフォーマットを取得する。
    /// アセットが未インストールの場合はダウンロードを要求する。
    func prepare() async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        self.transcriber = transcriber

        // アセットの状態を確認し、必要ならダウンロードを開始
        let status = await AssetInventory.status(forModules: [transcriber])
        if status < .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // SpeechAnalyzer に最適なオーディオフォーマットを問い合わせる
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        self.bestFormat = format

        try await analyzer.prepareToAnalyze(in: format)
    }

    /// キャプチャマネージャに渡すべき最適なオーディオフォーマットを返す。
    func targetAudioFormat() -> AVAudioFormat? {
        bestFormat
    }

    /// ストリーミング文字起こしを開始する。
    func startStreaming(store: TranscriptStore, bridge: AudioBufferBridge) async throws {
        guard let analyzer, let transcriber else { return }

        // SpeechAnalyzer にオーディオストリームを渡して解析開始
        try await analyzer.start(inputSequence: bridge.stream)

        let recordingStartTime = await store.recordingStartTime ?? Date()

        // SpeechTranscriber の結果を非同期でイテレーションし、TranscriptStore に反映
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard self != nil else { break }

                    let label = self?.speakerLabel
                    guard let text = Self.normalizedTranscriptText(String(result.text.characters)) else {
                        if result.isFinal {
                            Task { @MainActor in
                                store.replaceUnconfirmedSegments(with: [], forSource: label)
                            }
                        }
                        continue
                    }

                    let startSeconds = result.range.start.seconds
                    let endSeconds = result.range.end.seconds

                    let startDate = recordingStartTime.addingTimeInterval(
                        startSeconds.isFinite ? startSeconds : 0
                    )
                    let endDate = recordingStartTime.addingTimeInterval(
                        endSeconds.isFinite ? endSeconds : 0
                    )

                    let segment = TranscriptSegment(
                        startTime: startDate,
                        endTime: endDate,
                        text: text,
                        isConfirmed: result.isFinal,
                        speakerLabel: label
                    )

                    if result.isFinal {
                        Task { @MainActor in
                            store.replaceUnconfirmedSegments(with: [], forSource: label)
                            store.addSegment(segment)
                        }
                    } else {
                        Task { @MainActor in
                            store.replaceUnconfirmedSegments(with: [segment], forSource: label)
                        }
                    }
                }
            } catch {
                print("[SpeechTranscriberService] 結果イテレーションエラー: \(error)")
            }
        }
    }

    /// ストリーミング文字起こしを停止する。残りのバッファを処理してから終了。
    func stopStreaming() async {
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            print("[SpeechTranscriberService] 終了処理エラー: \(error)")
        }

        // 結果イテレーションタスクの完了を待機
        await resultTask?.value
        resultTask = nil
    }

    /// 即時キャンセル。残りのバッファは破棄する。
    func cancel() async {
        await analyzer?.cancelAndFinishNow()
        resultTask?.cancel()
        resultTask = nil
    }

    /// 状態をリセットする。
    func reset() {
        resultTask?.cancel()
        resultTask = nil
        analyzer = nil
        transcriber = nil
        bestFormat = nil
    }
}
