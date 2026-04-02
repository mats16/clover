import SwiftUI
import UniformTypeIdentifiers

/// メインコントロールウィンドウ（議事録ビュー）。
struct ControlPanelView: View {
    @ObservedObject var viewModel: CaptionViewModel
    @ObservedObject var sidebarViewModel: SidebarViewModel

    var body: some View {
        VStack(spacing: 12) {
            // 準備中プログレス
            if viewModel.isPreparingAnalyzer {
                ProgressView(L10n.preparingSpeechRecognition)
                    .progressViewStyle(.linear)
            }

            liveControls

            Divider()

            // 議事録表示エリア
            GroupBox {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(viewModel.store.segments) { segment in
                                TranscriptRowView(segment: segment)
                            }

                            // 録音中インジケータ
                            if viewModel.isListening {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 12, height: 12)
                                    Text(L10n.recognizing)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.leading, 68)
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(8)
                    }
                    .onChange(of: viewModel.store.segments.count) {
                        withAnimation {
                            proxy.scrollTo("bottom")
                        }
                    }
                }
            } label: {
                HStack {
                    Text(L10n.transcription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(L10n.segmentCount(viewModel.store.segments.count))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 280)

            // エラー表示
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
    }

    // MARK: - Live Recording Controls

    private var liveControls: some View {
        HStack(spacing: 12) {
            // 録音開始/停止ボタン
            Button(action: {
                if viewModel.isViewingHistory {
                    resumeRecording()
                } else {
                    guard let dbQueue = sidebarViewModel.dbQueue else { return }
                    viewModel.toggleListening(dbQueue: dbQueue)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: recordButtonIcon)
                        .font(.caption)
                    Text(recordButtonLabel)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(viewModel.isListening ? .white : .accentColor)
                .background(viewModel.isListening ? Color.red : Color.accentColor.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.analyzerReady || sidebarViewModel.selectedProject == nil)
            .keyboardShortcut(.space, modifiers: [])

            // 音声ソース選択
            HStack(spacing: 0) {
                ForEach(AudioSourceMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.audioSourceMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.iconName)
                                .font(.caption2)
                            Text(mode.label)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(viewModel.audioSourceMode == mode ? Color.accentColor : Color.clear)
                        .foregroundColor(viewModel.audioSourceMode == mode ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(viewModel.isListening)
            .frame(maxWidth: 260)

            // 言語選択
            Picker("", selection: Binding(
                get: { viewModel.selectedLocale },
                set: { viewModel.changeLocale($0) }
            )) {
                if viewModel.filteredLocales.isEmpty {
                    Text(Locale.current.localizedString(forIdentifier: viewModel.selectedLocale) ?? viewModel.selectedLocale)
                        .tag(viewModel.selectedLocale)
                }
                ForEach(viewModel.filteredLocales, id: \.identifier) { locale in
                    Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        .tag(locale.identifier)
                }
            }
            .frame(maxWidth: 160)

            Spacer()

            // 書き出し
            Button(action: { viewModel.exportTranscript() }) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.store.segments.isEmpty)
            .help(L10n.export)

            // クリア
            Button(action: { viewModel.clearText() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.store.segments.isEmpty || !viewModel.isListening)
            .help(L10n.clearTranscription)
        }
    }

    // MARK: - Actions

    private func resumeRecording() {
        guard let dbQueue = sidebarViewModel.dbQueue,
              let transcriptionId = viewModel.currentTranscriptionId else { return }
        Task {
            await viewModel.startListening(dbQueue: dbQueue, appendingTo: transcriptionId)
        }
    }

    // MARK: - Computed

    private var recordButtonIcon: String {
        if viewModel.isListening {
            return "stop.fill"
        } else if viewModel.isViewingHistory {
            return "arrow.counterclockwise"
        } else {
            return "circle.fill"
        }
    }

    private var recordButtonLabel: String {
        if viewModel.isListening {
            return L10n.stop
        } else if viewModel.isViewingHistory {
            return L10n.resume
        } else {
            return L10n.record
        }
    }

}
