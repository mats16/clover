import AppKit
import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

private extension View {
    @ViewBuilder
    func actionCursor(isEnabled: Bool = true) -> some View {
        if isEnabled {
            self.pointerStyle(.link)
        } else {
            self
        }
    }
}

private enum NotesEditorLayout {
    static let editorPadding = EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
    /// `TextEditor` keeps a small internal inset on macOS, so the placeholder needs
    /// a matching offset instead of using the same outer padding.
    static let placeholderPadding = EdgeInsets(top: 10, leading: 9, bottom: 0, trailing: 0)
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
}

/// Circleback 風タブバー。選択中はアンダーラインでアクティブを示す。
/// タブは左寄せで表示し、アクションボタンは画面下部のフローティングバーに配置する。
private struct DetailTabBar: View {
    @Binding var selection: DetailTab
    @ObservedObject var viewModel: CaptionViewModel
    let showsSummaryTab: Bool
    @Namespace private var tabNamespace

    /// フォルダ選択時（transcription 未選択）は全タブを無効化する。
    /// 録音中は録音対象が存在するためタブを無効化しない。
    private var isFolderOnly: Bool {
        viewModel.currentMeetingId == nil && !viewModel.isListening
    }

    private var visibleTabs: [DetailTab] {
        if showsSummaryTab {
            DetailTab.allCases
        } else {
            DetailTab.allCases.filter { $0 != .summary }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(visibleTabs) { tab in
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
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
    }
}

/// 画面下部にフローティング表示するアクションバー。
/// 設定メニュー・文字起こし開始/停止・スクリーンショット取得をまとめて配置する。
struct FloatingActionBar: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var recordingMeetingTitle: String?
    var onOpenRecordingMeeting: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if let recordingMeetingTitle, let onOpenRecordingMeeting {
                RecordingMeetingShortcutButton(
                    title: recordingMeetingTitle,
                    action: onOpenRecordingMeeting
                )
                FloatingActionBarSeparator()
            }
            SessionSettingsMenu(viewModel: viewModel)
            FloatingActionBarSeparator()
            TranscribeButton(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
            if shouldShowGenerateSummaryButton {
                FloatingActionBarSeparator()
                GenerateSummaryButton(viewModel: viewModel)
            }
            FloatingActionBarSeparator()
            ScreenshotButton(viewModel: viewModel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.background)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .allowsHitTesting(false)
        )
        .overlay(
            Capsule()
                .stroke(.quaternary, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private var shouldShowGenerateSummaryButton: Bool {
        !viewModel.isListening && viewModel.canGenerateSummary
    }
}

private struct FloatingActionBarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}

private struct RecordingMeetingShortcutButton: View {
    private static let labelFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private static let maxLabelWidth: CGFloat = 220

    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: measuredLabelWidth, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.quaternary)
                        .opacity(isHovered ? 1 : 0)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.quaternary, lineWidth: 1)
                        .allowsHitTesting(false)
                        .opacity(isHovered ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .actionCursor()
        .help(title)
        .accessibilityLabel(title)
    }

    private var measuredLabelWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.labelFont]
        let width = ceil((title as NSString).size(withAttributes: attributes).width)
        return min(width, Self.maxLabelWidth)
    }
}

/// セッション設定メニュー（AI Summary・文字起こし・スクリーンショット）。
private struct SessionSettingsMenu: View {
    @ObservedObject var viewModel: CaptionViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var summaryTemplates: [SummaryTemplate] = []
    @State private var isHovered = false
    private let templateService = SummaryTemplateService()

    var body: some View {
        Menu {
            // ── Summary ──
            Section(L10n.summary) {
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
                    Picker(selection: $viewModel.selectedMicrophoneID) {
                        Text(L10n.none).tag(AudioDeviceID?.none)

                        if !viewModel.availableMicrophones.isEmpty {
                            Divider()
                        }

                        ForEach(viewModel.availableMicrophones) { microphone in
                            Text(microphone.name).tag(AudioDeviceID?.some(microphone.id))
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: viewModel.selectedMicrophoneID) { oldValue, newValue in
                        viewModel.handleMicrophoneSelectionChange(from: oldValue, to: newValue)
                    }
                } label: {
                    Label(L10n.microphone, systemImage: "mic.fill")
                }
                .onAppear {
                    viewModel.refreshAvailableMicrophones()
                }

                Menu {
                    Picker(selection: $viewModel.isSystemAudioEnabled) {
                        Text(L10n.noComputerAudio).tag(false)
                        Text(L10n.recordComputerAudio).tag(true)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: viewModel.isSystemAudioEnabled) { oldValue, newValue in
                        viewModel.handleSystemAudioSelectionChange(from: oldValue, to: newValue)
                    }
                } label: {
                    Label(L10n.systemAudio, systemImage: "speaker.wave.2.fill")
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
            Section(L10n.screen) {
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
                    Label(L10n.source, systemImage: "photo.badge.plus")
                }
            }
        } label: {
            Label(L10n.settings, systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isHovered ? .tertiary : .quaternary)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.tertiary, lineWidth: 1)
                        .allowsHitTesting(false)
                        .opacity(isHovered ? 1 : 0)
                }
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
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .actionCursor()
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
    @State private var isHovered = false

    private var showsResumeStyle: Bool {
        !viewModel.isListening && viewModel.isViewingHistory
    }

    private var isEnabled: Bool {
        viewModel.isListening || (viewModel.hasEnabledAudioSource && viewModel.analyzerReady && sidebarViewModel.currentVault != nil)
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .bold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .contentShape(Capsule())
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(showsResumeStyle ? Color.primary : Color.white)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay {
                if showsResumeStyle {
                    Capsule()
                        .stroke(isHovered ? .tertiary : .quaternary, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: shadowColor,
                radius: isHovered ? 10 : 6,
                y: isHovered ? 3 : 2
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .actionCursor(isEnabled: isEnabled)
        .disabled(!isEnabled)
        .keyboardShortcut(.space, modifiers: [])
    }

    private var shadowColor: Color {
        if showsResumeStyle {
            return .clear
        }

        return .black.opacity(isHovered ? 0.18 : 0.12)
    }

    private var backgroundColor: Color {
        if viewModel.isListening {
            isHovered ? .red.opacity(0.88) : .red
        } else if showsResumeStyle {
            isHovered ? Color.primary.opacity(0.06) : .clear
        } else {
            isHovered ? .accentColor.opacity(0.88) : .accentColor
        }
    }

    private func toggle() {
        if viewModel.isListening {
            viewModel.stopListening()
            return
        }

        if viewModel.isViewingHistory {
            guard let dbQueue = sidebarViewModel.dbQueue,
                  let vault = sidebarViewModel.currentVault,
                  let meetingId = viewModel.currentMeetingId else { return }
            Task {
                await viewModel.startListening(
                    dbQueue: dbQueue,
                    projectURL: viewModel.currentProjectURL,
                    vaultId: vault.id,
                    projectId: viewModel.currentProjectId,
                    projectName: viewModel.currentProjectName,
                    vaultURL: vault.url,
                    appendingTo: meetingId
                )
            }
        } else {
            guard let dbQueue = sidebarViewModel.dbQueue,
                  let vault = sidebarViewModel.currentVault else { return }
            viewModel.toggleListening(
                dbQueue: dbQueue,
                projectURL: sidebarViewModel.selectedProjectURL,
                vaultId: vault.id,
                projectId: sidebarViewModel.selectedProject?.id,
                projectName: sidebarViewModel.selectedProject?.name,
                vaultURL: vault.url
            )
        }
    }

    private var iconName: String {
        viewModel.isListening ? "pause.fill" : "waveform"
    }

    private var label: String {
        if viewModel.isListening {
            "Pause"
        } else if showsResumeStyle {
            "Resume"
        } else {
            "Start recording"
        }
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
            .pointerStyle(.link)
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
                .pointerStyle(.link)
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
                .pointerStyle(.link)
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
    @State private var isHovered = false

    var body: some View {
        Button(L10n.screenshots, systemImage: "photo.badge.plus") {
            viewModel.takeScreenshot()
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.quaternary)
                .opacity(isHovered ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
                .allowsHitTesting(false)
                .opacity(isHovered ? 1 : 0)
        )
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .actionCursor(isEnabled: viewModel.canTakeScreenshot)
        .disabled(!viewModel.canTakeScreenshot)
        .help("スクリーンショットを撮影")
    }
}

/// 手動で要約を生成するボタン。
private struct GenerateSummaryButton: View {
    @ObservedObject var viewModel: CaptionViewModel
    @State private var isHovered = false

    private var isGeneratingCurrentMeeting: Bool {
        viewModel.summaryGeneratingMeetingId == viewModel.currentMeetingId
    }

    var body: some View {
        Button(action: viewModel.triggerManualSummary) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text(isGeneratingCurrentMeeting ? "Generating..." : "Generate summary")
                    .font(.system(size: 14, weight: .semibold))
            }
            .contentShape(Capsule())
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(
                Capsule()
                    .fill(isHovered ? Color.accentColor.opacity(0.88) : Color.accentColor)
            )
            .shadow(color: .black.opacity(isHovered ? 0.18 : 0.12), radius: isHovered ? 10 : 6, y: isHovered ? 3 : 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .actionCursor(isEnabled: !isGeneratingCurrentMeeting && viewModel.canGenerateSummary)
        .disabled(isGeneratingCurrentMeeting || !viewModel.canGenerateSummary)
    }
}

/// Circleback 風の個別タブボタン。選択中はアンダーラインでアクティブを示す。
private struct DetailTabButton: View {
    let tab: DetailTab
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? .primary : .tertiary)

                Spacer()
                    .frame(height: 3)
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 3)
                        .padding(.horizontal, 6)
                        .matchedGeometryEffect(id: "activeTab", in: namespace)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}

/// ミーティング詳細のタイトル。クリックでインライン編集できる。
private struct MeetingNameHeader: View {
    let meeting: MeetingRecord
    @Binding var isEditing: Bool
    @Binding var editingName: String
    @FocusState.Binding var isFocused: Bool
    let onBeginEditing: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onEditorTap: () -> Void

    private var displayName: String {
        let trimmed = meeting.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.newMeeting : trimmed
    }

    var body: some View {
        Group {
            if isEditing {
                TextField(L10n.title, text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .semibold))
                    .focused($isFocused)
                    .onSubmit(onCommit)
                    .onExitCommand(perform: onCancel)
                    .onChange(of: isFocused) { _, focused in
                        if !focused, isEditing {
                            onCommit()
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            onEditorTap()
                        }
                    )
                    .task {
                        editingName = meeting.name
                        try? await Task.sleep(for: .milliseconds(50))
                        isFocused = true
                    }
            } else {
                Button(action: onBeginEditing) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.rename)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: meeting.id) { _, _ in
            isEditing = false
            editingName = meeting.name
        }
        .onChange(of: meeting.name) { _, newName in
            if !isEditing {
                editingName = newName
            }
        }
    }
}

/// メインコントロールウィンドウ（議事録ビュー）。
struct ControlPanelView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    @State private var selectedTab: DetailTab = .notes
    @State private var expandedScreenshot: MeetingScreenshotRecord?
    @State private var isEditingMeetingName = false
    @State private var editingMeetingName = ""
    @State private var didTapInsideMeetingNameEditor = false
    @State private var didTapInsideNotesField = false
    @FocusState private var isMeetingNameFieldFocused: Bool
    @FocusState private var isNotesFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // 準備中プログレス
            if viewModel.isPreparingAnalyzer {
                ProgressView(L10n.preparingSpeechRecognition)
                    .progressViewStyle(.linear)
            }

            if let item = currentMeetingItem {
                MeetingNameHeader(
                    meeting: item.meeting,
                    isEditing: $isEditingMeetingName,
                    editingName: $editingMeetingName,
                    isFocused: $isMeetingNameFieldFocused,
                    onBeginEditing: beginMeetingRename,
                    onCommit: commitMeetingRename,
                    onCancel: cancelMeetingRename,
                    onEditorTap: markMeetingNameEditorTap
                )
                .padding(.top, -12)

                MeetingMetadataBar(
                    viewModel: viewModel,
                    meeting: item.meeting,
                    tags: item.tags,
                    sidebarViewModel: sidebarViewModel
                )
            }

            // タブ切り替え（左寄せ）
            DetailTabBar(selection: $selectedTab, viewModel: viewModel, showsSummaryTab: hasSummaryTab)

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
                    .fill(tabContentBackgroundColor)
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
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissFocusedInputs()
            }
        )
        .onChange(of: viewModel.requestShowSummaryTab) {
            updateSummaryTabSelection()
        }
        .onChange(of: hasSummaryTab) {
            updateSummaryTabSelection()
        }
        .onChange(of: currentMeetingItem?.meeting.id) { _, _ in
            if currentMeetingItem != nil {
                selectedTab = initialTabSelection
            }
            viewModel.requestShowSummaryTab = false
            cancelMeetingRename()
        }
        .navigationTitle(headerTitle)
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
        if let summary = viewModel.sanitizedMeetingSummary {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.currentMeetingActionItems.isEmpty {
                        MeetingActionItemsSection(viewModel: viewModel)
                    }

                    MarkdownContentView(markdown: summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView {
                Label(L10n.summary, systemImage: "list.bullet.clipboard")
            } description: {
                if persistedSummaryExists {
                    ProgressView()
                } else if viewModel.summaryGeneratingMeetingId == viewModel.currentMeetingId {
                    ProgressView(L10n.generatingSummary)
                } else {
                    Text("要約はまだ生成されていません")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var notesTabContent: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.noteText)
                        .font(.body)
                        .focused($isNotesFieldFocused)
                        .scrollContentBackground(.hidden)
                        .frame(height: notesEditorHeight(for: proxy.size.height))
                        .padding(NotesEditorLayout.editorPadding)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                didTapInsideNotesField = true
                            }
                        )

                    if viewModel.noteText.isEmpty {
                        Text(L10n.notesPlaceholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(NotesEditorLayout.placeholderPadding)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                )

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func notesEditorHeight(for availableHeight: CGFloat) -> CGFloat {
        let reservedBottomSpace: CGFloat = 96
        let minimumHeight: CGFloat = 140
        let preferredHeight = availableHeight * 0.85
        let maximumHeight = max(minimumHeight, availableHeight - reservedBottomSpace)
        return min(max(minimumHeight, preferredHeight), maximumHeight)
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

    private var currentMeetingItem: MeetingOverviewItem? {
        guard let meetingId = viewModel.currentMeetingId else { return nil }
        return sidebarViewModel.allMeetings.first(where: { $0.meetingId == meetingId })
    }

    private var persistedSummaryExists: Bool {
        currentMeetingItem?.hasSummary == true
    }

    private var hasSummaryTab: Bool {
        persistedSummaryExists || viewModel.hasCurrentMeetingSummary
    }

    private var tabContentBackgroundColor: Color {
        selectedTab == .notes ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor)
    }

    /// ヘッダーに表示する「プロジェクト名 - トランスクリプション名」。
    private var headerTitle: String {
        let item = currentMeetingItem
        let projectName = item?.projectName ?? L10n.noProject
        let meetingName: String = if let name = item?.meeting.name, !name.isEmpty {
            name
        } else {
            L10n.newMeeting
        }
        return "\(projectName) - \(meetingName)"
    }

    private func beginMeetingRename() {
        editingMeetingName = currentMeetingItem?.meeting.name ?? ""
        isEditingMeetingName = true
        didTapInsideMeetingNameEditor = false
    }

    private func cancelMeetingRename() {
        editingMeetingName = currentMeetingItem?.meeting.name ?? ""
        isEditingMeetingName = false
        isMeetingNameFieldFocused = false
        didTapInsideMeetingNameEditor = false
    }

    private func commitMeetingRename() {
        guard isEditingMeetingName, let meeting = currentMeetingItem?.meeting else { return }
        let trimmed = editingMeetingName.trimmingCharacters(in: .whitespacesAndNewlines)
        sidebarViewModel.renameMeeting(id: meeting.id, newName: trimmed)
        isEditingMeetingName = false
        isMeetingNameFieldFocused = false
        didTapInsideMeetingNameEditor = false
    }

    private func markMeetingNameEditorTap() {
        didTapInsideMeetingNameEditor = true
    }

    private func dismissFocusedInputs() {
        if didTapInsideMeetingNameEditor {
            didTapInsideMeetingNameEditor = false
        } else if isEditingMeetingName {
            isMeetingNameFieldFocused = false
        }

        if didTapInsideNotesField {
            didTapInsideNotesField = false
        } else if isNotesFieldFocused {
            isNotesFieldFocused = false
        }
    }

    private func updateSummaryTabSelection() {
        if hasSummaryTab, viewModel.requestShowSummaryTab {
            selectedTab = .summary
            viewModel.requestShowSummaryTab = false
        } else if !hasSummaryTab, selectedTab == .summary {
            selectedTab = .notes
        }
    }

    private var initialTabSelection: DetailTab {
        hasSummaryTab ? .summary : .notes
    }

}
