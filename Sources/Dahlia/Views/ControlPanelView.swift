import SwiftUI
import UniformTypeIdentifiers

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

/// Circleback 風タブバー。選択中はアンダーラインでアクティブを示す。
/// タブは左寄せで表示し、アクションボタンは画面下部のフローティングバーに配置する。
private struct DetailTabBar: View {
    @Binding var selection: DetailTab
    @ObservedObject var viewModel: CaptionViewModel
    @Namespace private var tabNamespace

    /// フォルダ選択時（transcription 未選択）は全タブを無効化する。
    /// 録音中は録音対象が存在するためタブを無効化しない。
    private var isFolderOnly: Bool {
        viewModel.currentMeetingId == nil && !viewModel.isListening
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
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
                Spacer(minLength: 0)
            }
            Divider()
        }
    }
}

/// 画面下部にフローティング表示するアクションバー。
/// 設定メニュー・文字起こし開始/停止・スクリーンショット取得をまとめて配置する。
private struct FloatingActionBar: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel

    var body: some View {
        HStack(spacing: 6) {
            SessionSettingsMenu(viewModel: viewModel)
            TranscribeButton(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
            ScreenshotButton(viewModel: viewModel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.background)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(.quaternary, lineWidth: 1)
        )
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
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(
                Capsule()
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
                  let meetingId = viewModel.currentMeetingId else { return }
            Task {
                await viewModel.startListening(
                    dbQueue: dbQueue,
                    projectURL: projectURL,
                    projectId: project.id,
                    projectName: project.name,
                    vaultURL: vaultURL,
                    appendingTo: meetingId
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
    let screenshot: MeetingScreenshotRecord
    let viewModel: CaptionViewModel
    @Binding var expandedScreenshot: MeetingScreenshotRecord?

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
        .disabled(viewModel.currentMeetingId == nil)
        .help("スクリーンショットを撮影")
    }
}

/// Circleback 風の個別タブボタン。選択中はアンダーラインでアクティブを示す。
private struct DetailTabButton: View {
    let tab: DetailTab
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12))
                    Text(tab.label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? .primary : .tertiary)

                // アクティブインジケーター
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
                    .matchedGeometryEffect(id: isSelected ? "activeTab" : "tab-\(tab.id)", in: namespace)
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
    @Binding var isAgentSidebarPresented: Bool
    @State private var selectedTab: DetailTab = .transcript
    @State private var expandedScreenshot: MeetingScreenshotRecord?
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        VStack(spacing: 12) {
            // 準備中プログレス
            if viewModel.isPreparingAnalyzer {
                ProgressView(L10n.preparingSpeechRecognition)
                    .progressViewStyle(.linear)
            }

            // タブ切り替え（左寄せ）
            DetailTabBar(selection: $selectedTab, viewModel: viewModel)

            // タブコンテンツ
            Group {
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
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.currentMeetingId != nil {
                    Button(L10n.export, systemImage: "square.and.arrow.up", action: exportTranscript)
                        .labelStyle(.iconOnly)
                        .disabled(viewModel.store.segments.isEmpty)
                        .help(L10n.export)
                }

                if appSettings.agentEnabled {
                    Button(action: toggleAgentSidebar) {
                        Label(L10n.agent, systemImage: "sparkles")
                            .foregroundStyle(isAgentRunning ? .purple : .secondary)
                    }
                    .help(L10n.agent)
                }
            }
        }
        .overlay(alignment: .bottom) {
            FloatingActionBar(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                .padding(.bottom, 20)
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
                if viewModel.summaryGeneratingMeetingId == viewModel.currentMeetingId {
                    ProgressView(L10n.generatingSummary)
                } else {
                    Text("要約はまだ生成されていません")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

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

                            // 録音中インジケータ（録音対象のトランスクリプト表示中のみ）
                            if viewModel.isListening, !viewModel.isViewingOtherWhileRecording {
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

    // MARK: - Computed

    private var isAgentRunning: Bool {
        viewModel.agentService?.isRunning == true
    }

    /// ヘッダーに表示する「プロジェクト名 - トランスクリプション名」。
    private var headerTitle: String {
        guard let project = sidebarViewModel.selectedProject else { return "" }
        let meetingName: String = if let meetingId = viewModel.currentMeetingId,
                                     let record = sidebarViewModel.meetingsForSelectedProject.first(where: { $0.id == meetingId }) {
            record.name.isEmpty ? L10n.newMeeting : record.name
        } else {
            L10n.newMeeting
        }
        return "\(project.name) - \(meetingName)"
    }

    private func exportTranscript() {
        viewModel.exportTranscript()
    }

    private func toggleAgentSidebar() {
        isAgentSidebarPresented.toggle()
    }

}
