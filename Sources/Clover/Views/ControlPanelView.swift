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
        case .screenshots: "camera.viewfinder"
        case .transcript: "waveform.badge.microphone"
        }
    }
}

/// Notion 風タブバー。選択中はピル型背景、ホバーで薄いハイライト。
private struct DetailTabBar: View {
    @Binding var selection: DetailTab
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { tab in
                DetailTabButton(
                    tab: tab,
                    isSelected: selection == tab
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = tab
                    }
                }
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
    @State private var isHovered = false
    @State private var summaryTemplates: [SummaryTemplate] = []
    private let templateService = SummaryTemplateService()

    var body: some View {
        Menu {
            // ── AI Summary ──
            Section("AI Summary") {
                Button {
                    viewModel.triggerManualSummary()
                } label: {
                    Label("Retry summary", systemImage: "pencil.and.scribble")
                }
                .disabled(viewModel.isSummaryGenerating || !viewModel.canGenerateSummary)

                Toggle(isOn: $appSettings.llmAutoSummaryEnabled) {
                    Label("終了時に自動要約", systemImage: "long.text.page.and.pencil")
                }

                Menu {
                    Picker(selection: $appSettings.llmSummaryLanguageRawValue) {
                        ForEach(SummaryLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label("Language", systemImage: "globe")
                }

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

                    Button {
                        createNewTemplate()
                    } label: {
                        Label("Add custom instructions", systemImage: "plus")
                    }
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
                    Picker(selection: Binding(
                        get: { viewModel.selectedLocale },
                        set: { viewModel.changeLocale($0) }
                    )) {
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
                    Label("Capture source", systemImage: "inset.filled.rectangle.and.person.filled")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                viewModel.refreshAvailableWindows()
            }
        }
        .pointerStyle(.link)
        .task { loadSummaryTemplates() }
        .onChange(of: appSettings.currentVault?.id) { loadSummaryTemplates() }
    }

    private func loadSummaryTemplates() {
        guard let vaultURL = appSettings.vaultURL else { return }
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
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

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
            .foregroundColor(viewModel.isListening ? .white : .white)
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
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 20)
                .padding(24)
                .onTapGesture { onDismiss() }
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
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .pointerStyle(.link)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            expandedScreenshot = screenshot
                        }
                    }
            }
            HStack {
                Text(Self.timeFormatter.string(from: screenshot.capturedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    viewModel.deleteScreenshot(screenshot)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

/// スクリーンショット撮影ボタン。
private struct ScreenshotButton: View {
    @ObservedObject var viewModel: CaptionViewModel

    var body: some View {
        Button(action: { viewModel.takeScreenshot() }) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(viewModel.currentTranscriptionId == nil)
        .help("スクリーンショットを撮影")
    }
}

/// Notion 風の個別タブボタン。
private struct DetailTabButton: View {
    let tab: DetailTab
    let isSelected: Bool
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
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(0.08)
                            : isHovered ? Color.primary.opacity(0.04) : Color.clear
                    )
            )
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
    @ObservedObject private var appSettings = AppSettings.shared
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
            GroupBox {
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
                    Button(action: { viewModel.exportTranscript() }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.store.segments.isEmpty)
                    .help(L10n.export)
                }
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
                if viewModel.isSummaryGenerating {
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
        ContentUnavailableView {
            Label(L10n.notes, systemImage: "pencil.line")
        } description: {
            Text("ノート機能は準備中です")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var screenshotsTabContent: some View {
        if viewModel.screenshots.isEmpty {
            ContentUnavailableView {
                Label(L10n.screenshots, systemImage: "camera.viewfinder")
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

    @ViewBuilder
    private var transcriptTabContent: some View {
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
    }

    // MARK: - Computed

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


}
