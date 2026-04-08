import SwiftUI
import UniformTypeIdentifiers

/// ホバー時に背景がハイライトされるアイコンボタンスタイル。
struct ToolbarIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed
                        ? Color.primary.opacity(0.15)
                        : isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// 音声ソース選択ボタン（ホバー対応）。
private struct AudioSourceButton: View {
    let mode: AudioSourceMode
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.iconName)
                    .font(.caption2)
                Text(mode.label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? Color.accentColor
                    : isHovered ? Color.primary.opacity(0.08) : Color.clear
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// メインコントロールウィンドウ（議事録ビュー）。
struct ControlPanelView: View {
    @ObservedObject var viewModel: CaptionViewModel
    @ObservedObject var sidebarViewModel: SidebarViewModel
    @ObservedObject private var appSettings = AppSettings.shared

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

            // 要約ステータス
            if viewModel.isSummaryGenerating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.generatingSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let summaryError = viewModel.summaryError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(summaryError)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
            }

            if let summaryURL = viewModel.lastSummaryURL {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(L10n.summaryGenerated)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(L10n.openSummary) {
                        AppSettings.shared.markdownEditor.open(summaryURL)
                    }
                    .font(.caption)
                    Spacer()
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
        .navigationTitle(headerTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.currentTranscriptionId != nil {
                    Button(action: { viewModel.exportTranscript() }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.store.segments.isEmpty)
                    .help(L10n.export)
                }
            }
        }
    }

    // MARK: - Live Recording Controls

    private var liveControls: some View {
        HStack(spacing: 12) {
            // 録音開始/停止ボタン
            Button(action: {
                if viewModel.isViewingHistory {
                    resumeRecording()
                } else {
                    guard let dbQueue = sidebarViewModel.dbQueue,
                          let projectURL = sidebarViewModel.selectedProjectURL,
                          let project = sidebarViewModel.selectedProject,
                          let vaultURL = sidebarViewModel.currentVault?.url else { return }
                    viewModel.toggleListening(dbQueue: dbQueue, projectURL: projectURL, projectId: project.id, projectName: project.name, vaultURL: vaultURL)
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
            .disabled(!viewModel.analyzerReady || sidebarViewModel.selectedProjectURL == nil)
            .keyboardShortcut(.space, modifiers: [])

            // 音声ソース選択
            HStack(spacing: 0) {
                ForEach(AudioSourceMode.allCases, id: \.self) { mode in
                    AudioSourceButton(
                        mode: mode,
                        isSelected: viewModel.audioSourceMode == mode
                    ) {
                        viewModel.audioSourceMode = mode
                    }
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

            // 要約生成 + テンプレート選択
            ControlGroup {
                Button(action: {
                    guard let transcriptionId = viewModel.currentTranscriptionId,
                          let projectURL = sidebarViewModel.selectedProjectURL else { return }
                    let text = viewModel.store.exportForSummary()
                    Task {
                        await viewModel.generateSummary(
                            transcriptionId: transcriptionId,
                            transcriptText: text,
                            projectURL: projectURL,
                            startedAt: viewModel.store.recordingStartTime ?? Date()
                        )
                    }
                }) {
                    Label(L10n.generateSummary, systemImage: "sparkles")
                }

                Menu {
                    ForEach(availableTemplates) { template in
                        Button(action: {
                            appSettings.selectedTemplateName = template.name
                        }) {
                            if template.name == appSettings.selectedTemplateName {
                                Label(template.displayName, systemImage: "checkmark")
                            } else {
                                Text(template.displayName)
                            }
                        }
                    }
                } label: {
                    Text(selectedTemplateDisplayName)
                }
            }
            .disabled(isSummaryDisabled)


        }
    }

    // MARK: - Actions

    private func resumeRecording() {
        guard let dbQueue = sidebarViewModel.dbQueue,
              let projectURL = sidebarViewModel.selectedProjectURL,
              let project = sidebarViewModel.selectedProject,
              let vaultURL = sidebarViewModel.currentVault?.url,
              let transcriptionId = viewModel.currentTranscriptionId else { return }
        Task {
            await viewModel.startListening(
                dbQueue: dbQueue,
                projectURL: projectURL,
                projectId: project.id,
                projectName: project.name,
                vaultURL: vaultURL,
                appendingTo: transcriptionId
            )
        }
    }

    // MARK: - Computed

    /// 要約ボタン・テンプレート選択を無効化する条件。
    private var isSummaryDisabled: Bool {
        viewModel.currentTranscriptionId == nil
            || viewModel.store.segments.isEmpty
            || viewModel.isSummaryGenerating
            || viewModel.isListening
    }

    /// 選択中テンプレートの表示名。
    private var selectedTemplateDisplayName: String {
        let name = appSettings.selectedTemplateName
        return availableTemplates.first(where: { $0.name == name })?.displayName
            ?? name.replacingOccurrences(of: "_", with: " ")
    }

    /// 保管庫内のテンプレート一覧。
    private var availableTemplates: [SummaryTemplate] {
        guard let vaultURL = sidebarViewModel.currentVault?.url else { return [] }
        return (try? SummaryTemplateService().fetchTemplates(in: vaultURL)) ?? []
    }

    /// ヘッダーに表示する「プロジェクト名 - トランスクリプション名」。
    private var headerTitle: String {
        guard let project = sidebarViewModel.selectedProject else { return "" }
        let transcriptName: String
        if let transcriptionId = viewModel.currentTranscriptionId,
           let record = sidebarViewModel.transcriptionsForSelectedProject.first(where: { $0.id == transcriptionId }) {
            transcriptName = record.title.isEmpty
                ? Self.headerDateFormatter.string(from: record.startedAt)
                : record.title
        } else {
            transcriptName = "new"
        }
        return "\(project.name) - \(transcriptName)"
    }

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    private var recordButtonIcon: String {
        if viewModel.isListening {
            "stop.fill"
        } else if viewModel.isViewingHistory {
            "arrow.counterclockwise"
        } else {
            "circle.fill"
        }
    }

    private var recordButtonLabel: String {
        if viewModel.isListening {
            L10n.stop
        } else if viewModel.isViewingHistory {
            L10n.resume
        } else {
            L10n.record
        }
    }

}
