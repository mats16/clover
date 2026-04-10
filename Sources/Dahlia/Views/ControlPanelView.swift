import SwiftUI
import UniformTypeIdentifiers

/// ホバー時に背景がハイライトされるアイコンボタンスタイル。
struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 5))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .pointerStyle(.link)
    }
}

/// メイン領域のタブ種別。
enum DetailTab: String, CaseIterable, Identifiable {
    case summary
    case notes
    case screenshots
    case transcript

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary: L10n.summary
        case .notes: L10n.notes
        case .screenshots: L10n.screenshots
        case .transcript: L10n.transcript
        }
    }

    var icon: String {
        switch self {
        case .summary: "text.badge.checkmark"
        case .notes: "pencil.line"
        case .screenshots: "photo.on.rectangle.angled"
        case .transcript: "waveform.badge.microphone"
        }
    }
}

/// Notion 風タブバー。選択中はピル型 Liquid Glass 背景がスライドする。
private struct DetailTabBar: View {
    @Binding var selection: DetailTab
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    @Namespace private var tabNamespace

    /// フォルダ選択時（transcription 未選択）は全タブを無効化する。
    private var isFolderOnly: Bool {
        viewModel.currentTranscriptionId == nil
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { tab in
                DetailTabButton(
                    tab: tab,
                    isSelected: !isFolderOnly && selection == tab,
                    namespace: tabNamespace,
                    action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selection = tab
                        }
                    }
                )
                .disabled(isFolderOnly)
            }
            Spacer()
            SessionSettingsMenu(viewModel: viewModel)
            TranscribeButton(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
            ScreenshotButton(viewModel: viewModel)
        }
    }
}

/// セッション設定メニュー（AI Summary・文字起こし・スクリーンショット）。
private struct SessionSettingsMenu: View {
    @ObservedObject var viewModel: CaptionViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var summaryTemplates: [SummaryTemplate] = []
    private let templateService = SummaryTemplateService()

    var body: some View {
        Menu {
            // ── AI Summary ──
            Section("AI Summary") {
                Button("Retry summary", systemImage: "pencil.and.scribble") {
                    viewModel.triggerManualSummary()
                }
                .disabled(viewModel.isSummaryGenerating || !viewModel.canGenerateSummary)

                Menu {
                    Picker(selection: $appSettings.selectedTemplateName) {
                        Text("Auto").tag(AppSettings.autoTemplateName)

                        Divider()

                        ForEach(summaryTemplates) { template in
                            Text(template.displayName).tag(template.name)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Divider()

                    Button("Add custom instructions", systemImage: "plus", action: createNewTemplate)
                } label: {
                    Label("Instructions", systemImage: "pencil.line")
                }
            }

            // ── Transcribe ──
            Section("Transcribe") {
                Menu {
                    Picker(selection: $viewModel.audioSourceMode) {
                        ForEach(AudioSourceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(viewModel.isListening)
                } label: {
                    Label("Audio source", systemImage: "waveform.badge.microphone")
                }

                Menu {
                    Picker(selection: $viewModel.selectedLocale) {
                        if viewModel.filteredLocales.isEmpty {
                            let id = viewModel.selectedLocale
                            let name = Locale.current.localizedString(forIdentifier: id) ?? id
                            Text(name).tag(id)
                        } else {
                            ForEach(viewModel.filteredLocales, id: \.identifier) { locale in
                                let id = locale.identifier
                                let name = locale.localizedString(forIdentifier: id) ?? id
                                Text(name).tag(id)
                            }
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: viewModel.selectedLocale) { oldValue, newValue in
                        viewModel.handleLocaleSelectionChange(from: oldValue, to: newValue)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                }
            }

            // ── Screenshots ──
            Section("Screenshots") {
                Menu {
                    Picker(selection: $viewModel.selectedWindowID) {
                        Text("デスクトップ全体").tag(CGWindowID?.none)

                        Divider()

                        ForEach(viewModel.availableWindows, id: \.windowID) { window in
                            let appName = window.owningApplication?.applicationName ?? "不明"
                            let title = window.title ?? ""
                            let displayName = title.isEmpty ? appName : "\(appName) — \(title)"
                            Text(displayName).tag(CGWindowID?.some(window.windowID))
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label("Capture source", systemImage: "photo.badge.plus")
                }
            }
        } label: {
            Label(L10n.settings, systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.quaternary)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            if hovering {
                viewModel.refreshAvailableWindows()
            }
        }
        .pointerStyle(.link)
        .task { loadSummaryTemplates() }
        .onChange(of: appSettings.currentVault?.id) { _, _ in loadSummaryTemplates() }
    }

    private func loadSummaryTemplates() {
        guard let vaultURL = appSettings.vaultURL else {
            summaryTemplates = []
            return
        }
        try? templateService.seedPresets(in: vaultURL)
        summaryTemplates = (try? templateService.fetchTemplates(in: vaultURL)) ?? []
    }

    private func createNewTemplate() {
        guard let vaultURL = appSettings.vaultURL else { return }
        let dir = SummaryTemplateService.templatesDirectoryURL(in: vaultURL)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // ユニークなファイル名を生成
        var name = "new_template"
        var counter = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(name).md").path) {
            name = "new_template_\(counter)"
            counter += 1
        }

        let fileURL = dir.appendingPathComponent("\(name).md")
        _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        // テンプレート一覧を更新して新しいテンプレートを選択
        loadSummaryTemplates()
        appSettings.selectedTemplateName = name

        // エディタで開く
        appSettings.markdownEditor.open(fileURL)
    }
}

/// 文字起こし開始/停止ボタン。
private struct TranscribeButton: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(viewModel.isListening ? Color.red : Color.accentColor)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(!viewModel.analyzerReady || sidebarViewModel.selectedProjectURL == nil)
        .keyboardShortcut(.space, modifiers: [])
    }

    private func toggle() {
        if viewModel.isViewingHistory {
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
        } else {
            guard let dbQueue = sidebarViewModel.dbQueue,
                  let projectURL = sidebarViewModel.selectedProjectURL,
                  let project = sidebarViewModel.selectedProject,
                  let vaultURL = sidebarViewModel.currentVault?.url else { return }
            viewModel.toggleListening(
                dbQueue: dbQueue,
                projectURL: projectURL,
                projectId: project.id,
                projectName: project.name,
                vaultURL: vaultURL
            )
        }
    }

    private var iconName: String {
        viewModel.isListening ? "stop.fill" : "circle.fill"
    }

    private var label: String {
        viewModel.isListening ? "Stop transcribing" : "Start transcribing"
    }
}

/// スクリーンショット拡大表示オーバーレイ。
private struct ScreenshotOverlayView: View {
    let image: NSImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.close)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 20)
                .padding(24)

            Button(L10n.close, systemImage: "xmark.circle.fill", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.title3)
                .padding(16)
                .buttonStyle(.plain)
        }
    }
}

/// スクリーンショットのサムネイル表示。
private struct ScreenshotThumbnailView: View {
    let screenshot: ScreenshotRecord
    let viewModel: CaptionViewModel
    @Binding var expandedScreenshot: ScreenshotRecord?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            if let nsImage = NSImage(data: screenshot.imageData) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        expandedScreenshot = screenshot
                    }
                } label: {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .accessibilityLabel(L10n.open)
            }
            HStack {
                Text(Self.timeFormatter.string(from: screenshot.capturedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.delete, systemImage: "trash", role: .destructive) {
                    viewModel.deleteScreenshot(screenshot)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// スクリーンショット撮影ボタン。
private struct ScreenshotButton: View {
    @ObservedObject var viewModel: CaptionViewModel

    var body: some View {
        Button(L10n.screenshots, systemImage: "photo.badge.plus") {
            viewModel.takeScreenshot()
        }
        .labelStyle(.iconOnly)
        .font(.body)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(viewModel.currentTranscriptionId == nil)
        .help("スクリーンショットを撮影")
    }
}

/// Notion 風の個別タブボタン。選択中は Liquid Glass 背景がスライドする。
private struct DetailTabButton: View {
    let tab: DetailTab
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                Text(tab.label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background {
                if !isSelected, isHovered {
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                }
            }
            .background {
                if isSelected {
                    Capsule()
                        .fill(.quaternary)
                        .matchedGeometryEffect(id: "activeTab", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// メインコントロールウィンドウ（議事録ビュー）。
struct ControlPanelView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    @State private var selectedTab: DetailTab = .transcript
    @State private var expandedScreenshot: ScreenshotRecord?

    var body: some View {
        VStack(spacing: 12) {
            // 準備中プログレス
            if viewModel.isPreparingAnalyzer {
                ProgressView(L10n.preparingSpeechRecognition)
                    .progressViewStyle(.linear)
            }

            // タブ切り替え
            DetailTabBar(selection: $selectedTab, viewModel: viewModel, sidebarViewModel: sidebarViewModel)

            // タブコンテンツ
            Group {
                if viewModel.currentTranscriptionId == nil {
                    newTranscriptionPlaceholder
                } else {
                    switch selectedTab {
                    case .summary:
                        summaryTabContent
                    case .notes:
                        notesTabContent
                    case .screenshots:
                        screenshotsTabContent
                    case .transcript:
                        transcriptTabContent
                    }
                }
            }
            .frame(minHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background.secondary)
            )

            // エラー表示
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
            }

            if let summaryError = viewModel.summaryError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(summaryError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
            }

        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
        .onChange(of: viewModel.requestShowSummaryTab) {
            if viewModel.requestShowSummaryTab {
                selectedTab = .summary
                viewModel.requestShowSummaryTab = false
            }
        }
        .navigationTitle(headerTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.currentTranscriptionId != nil {
                    Button(L10n.export, systemImage: "square.and.arrow.up") {
                        viewModel.exportTranscript()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(viewModel.store.segments.isEmpty)
                    .help(L10n.export)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.summaryProgress.isVisible {
                SummaryProgressToastView(state: viewModel.summaryProgress)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.summaryProgress.isVisible)
            }
        }
        .overlay {
            if let screenshot = expandedScreenshot,
               let nsImage = NSImage(data: screenshot.imageData) {
                ScreenshotOverlayView(image: nsImage) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        expandedScreenshot = nil
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Tab Contents

    @ViewBuilder
    private var summaryTabContent: some View {
        if let summaryURL = viewModel.lastSummaryURL {
            VStack {
                Spacer()
                Button(L10n.openSummary) {
                    AppSettings.shared.markdownEditor.open(summaryURL)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(L10n.summary, systemImage: "list.bullet.clipboard")
            } description: {
                if viewModel.summaryGeneratingTranscriptionId == viewModel.currentTranscriptionId {
                    ProgressView(L10n.generatingSummary)
                } else {
                    Text("要約はまだ生成されていません")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var notesTabContent: some View {
        TextEditor(text: $viewModel.noteText)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background {
                if viewModel.noteText.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.notes, systemImage: "pencil.line")
                    } description: {
                        Text("ノートはまだありません")
                    }
                }
            }
    }

    @ViewBuilder
    private var screenshotsTabContent: some View {
        if viewModel.screenshots.isEmpty {
            ContentUnavailableView {
                Label(L10n.screenshots, systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("スクリーンショットはまだありません")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.screenshots, id: \.id) { screenshot in
                        ScreenshotThumbnailView(screenshot: screenshot, viewModel: viewModel, expandedScreenshot: $expandedScreenshot)
                    }
                }
                .padding(12)
            }
        }
    }

    private var transcriptTabContent: some View {
        Group {
            if viewModel.store.segments.isEmpty, !viewModel.isListening {
                ContentUnavailableView {
                    Label(L10n.transcript, systemImage: "waveform.badge.microphone")
                } description: {
                    Text("文字起こしはまだありません")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                                        .foregroundStyle(.secondary)
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
            }
        }
    }

    /// フォルダ選択時に表示する新規文字起こし作成プレースホルダー。
    private var newTranscriptionPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Button(L10n.newTranscription, systemImage: "plus.circle", action: createNewTranscription)
                .labelStyle(.iconOnly)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .pointerStyle(.link)
            Text(L10n.newTranscription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func createNewTranscription() {
        guard let project = sidebarViewModel.selectedProject,
              let dbQueue = sidebarViewModel.dbQueue,
              let projectURL = sidebarViewModel.selectedProjectURL,
              let vault = sidebarViewModel.currentVault
        else { return }

        viewModel.createEmptyTranscription(
            dbQueue: dbQueue,
            projectURL: projectURL,
            projectId: project.id,
            projectName: project.name,
            vaultURL: vault.url
        )

        if let newId = viewModel.currentTranscriptionId {
            sidebarViewModel.selectTranscription(newId)
        }
    }

    // MARK: - Computed

    /// ヘッダーに表示する「プロジェクト名 - トランスクリプション名」。
    private var headerTitle: String {
        guard let project = sidebarViewModel.selectedProject else { return "" }
        let transcriptName: String = if let transcriptionId = viewModel.currentTranscriptionId,
                                        let record = sidebarViewModel.transcriptionsForSelectedProject.first(where: { $0.id == transcriptionId }) {
            record.title.isEmpty
                ? Self.headerDateFormatter.string(from: record.startedAt)
                : record.title
        } else {
            "new"
        }
        return "\(project.name) - \(transcriptName)"
    }

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

}
