import SwiftUI

/// Agent 右サイドバーのコンテンツビュー。初期チャット入力画面またはチャット UI を表示する。
struct AgentSidebarView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let service = viewModel.agentService {
                AgentChatView(
                    service: service,
                    projectName: headerDirectoryName(service: service)
                ) {
                    viewModel.stopAgent()
                }
            } else {
                AgentLauncherView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
            }
        }
    }

    // MARK: - Agent Header

    private func headerDirectoryName(service: AgentService) -> String {
        if let projectName = service.workingDirectoryURL?.lastPathComponent,
           !projectName.isEmpty {
            return projectName
        }

        if let projectName = sidebarViewModel.selectedProject?.name ?? viewModel.currentProjectName,
           !projectName.isEmpty {
            return projectName
        }

        if let workingDirectory = viewModel.currentProjectURL ?? sidebarViewModel.currentVault?.url ?? viewModel.currentVaultURL {
            return workingDirectory.lastPathComponent
        }

        return L10n.agent
    }
}

/// Agent 起動前のランチャー画面。テキスト入力でプロジェクトモード、空入力で Transcript ボタンを表示。
private struct AgentLauncherView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    @State private var inputText = ""
    @FocusState private var isTextFieldFocused: Bool

    private var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var effectiveProjectURL: URL? {
        sidebarViewModel.selectedProjectURL ?? viewModel.currentProjectURL
    }

    private var effectiveProjectId: UUID? {
        sidebarViewModel.selectedProject?.id ?? viewModel.currentProjectId
    }

    private var effectiveProjectName: String? {
        sidebarViewModel.selectedProject?.name ?? viewModel.currentProjectName
    }

    private var effectiveWorkingDirectory: URL? {
        effectiveProjectURL ?? sidebarViewModel.currentVault?.url ?? viewModel.currentVaultURL
    }

    private var isDisabled: Bool {
        effectiveWorkingDirectory == nil
    }

    private var contextName: String? {
        effectiveProjectName ?? sidebarViewModel.currentVault?.name
    }

    private var launcherSuggestions: [String] {
        [
            L10n.askSuggestionMeetingPrep,
            L10n.askSuggestionRecentDiscussion,
            L10n.askSuggestionActionItems,
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AskLauncherMetrics.sectionSpacing) {
                    Spacer(minLength: AskLauncherMetrics.topSpacing)

                    VStack(spacing: AskLauncherMetrics.headerSpacing) {
                        if let contextName, !contextName.isEmpty {
                            Label(contextName, systemImage: "folder")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.background.secondary, in: Capsule())
                        }

                        Text(L10n.ask)
                            .font(.system(size: AskLauncherMetrics.titleSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(L10n.askLauncherSubtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: AskLauncherMetrics.cardSpacing) {
                        TextField(L10n.askPromptPlaceholder, text: $inputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: AskLauncherMetrics.promptSize, weight: .regular, design: .rounded))
                            .lineLimit(1 ... 5)
                            .focused($isTextFieldFocused)
                            .disabled(isDisabled)
                            .onSubmit {
                                guard hasContent else { return }
                                launchProjectMode()
                            }

                        HStack(alignment: .center, spacing: 12) {
                            Button(action: launchTranscriptMode) {
                                Label(L10n.agentTranscriptMode, systemImage: "waveform.badge.magnifyingglass")
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isDisabled ? .tertiary : .secondary)
                            .disabled(isDisabled)
                            .help(L10n.agentTranscriptModeDescription)

                            Spacer(minLength: 0)

                            Button(action: launchProjectMode) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(hasContent ? .primary : .tertiary)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle()
                                            .fill(hasContent ? Color.secondary.opacity(0.14) : Color.secondary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasContent || isDisabled)
                            .help(L10n.agentProjectMode)
                        }
                    }
                    .padding(AskLauncherMetrics.cardPadding)
                    .background(askLauncherCardBackground)

                    VStack(alignment: .leading, spacing: AskLauncherMetrics.suggestionSpacing) {
                        ForEach(launcherSuggestions, id: \.self) { suggestion in
                            Button {
                                guard !isDisabled else { return }
                                inputText = suggestion
                                launchProjectMode()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 18)

                                    Text(suggestion)
                                        .font(.title3)
                                        .foregroundStyle(isDisabled ? .tertiary : .secondary)
                                        .multilineTextAlignment(.leading)

                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isDisabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: AskLauncherMetrics.bottomSpacing)
                }
                .frame(
                    maxWidth: AskLauncherMetrics.maxContentWidth,
                    minHeight: max(proxy.size.height, AskLauncherMetrics.minHeight),
                    alignment: .top
                )
                .padding(.horizontal, AskLauncherMetrics.outerPadding)
                .frame(maxWidth: .infinity)
            }
            .background(askLauncherBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }

    private func launchProjectMode() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        viewModel.startAgent(mode: .project, initialMessage: message, workingDirectory: effectiveWorkingDirectory)
        inputText = ""
    }

    private func launchTranscriptMode() {
        Task {
            // 録音中でなければ文字起こしも同時に開始する
            if !viewModel.isListening,
               let dbQueue = sidebarViewModel.dbQueue,
               let vault = sidebarViewModel.currentVault {
                await viewModel.startListening(
                    dbQueue: dbQueue,
                    projectURL: effectiveProjectURL,
                    vaultId: vault.id,
                    projectId: effectiveProjectId,
                    projectName: effectiveProjectName,
                    vaultURL: vault.url
                )
            }

            viewModel.startAgent(
                mode: .transcript(store: viewModel.activeTranscriptStoreForAgent),
                initialMessage: "文字起こしモードを開始します。リアルタイムの文字起こしが随時送信されます。準備ができたら教えてください。",
                workingDirectory: effectiveWorkingDirectory
            )
        }
    }
}

/// AgentService を直接 @ObservedObject で監視するチャットビュー。
private struct AgentChatView: View {
    @ObservedObject var service: AgentService
    let projectName: String
    let onStop: () -> Void
    @State private var inputText = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // メッセージ一覧
            if service.messages.isEmpty {
                VStack(spacing: 12) {
                    if service.isRunning {
                        ProgressView()
                        Text("Claude Code を起動中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView {
                            Label(L10n.agent, systemImage: "sparkles")
                        } description: {
                            Text("Agent の出力はまだありません")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, AgentFloatingInputMetrics.contentBottomInset)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(service.messages) { message in
                                ChatBubbleView(message: message)
                            }

                            if service.isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(L10n.agentProcessing)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 36)
                            }

                            // スクロールアンカー
                            Color.clear
                                .frame(height: 1)
                                .id("agent-bottom")
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, AgentFloatingInputMetrics.scrollBottomInset)
                    }
                    .onAppear {
                        proxy.scrollTo("agent-bottom", anchor: .bottom)
                    }
                    .onChange(of: service.messages.count) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("agent-bottom", anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                AgentSessionBar(
                    projectName: projectName,
                    isLiveMode: service.mode.isTranscript,
                    onStop: onStop
                )

                ChatInputBar(
                    text: $inputText,
                    isEnabled: service.isRunning
                ) {
                    let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !message.isEmpty else { return }
                    service.sendUserMessage(message)
                    inputText = ""
                }
            }
            .padding(.bottom, AgentFloatingInputMetrics.bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentSessionBar: View {
    let projectName: String
    let isLiveMode: Bool
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(projectName, systemImage: "folder.fill")
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if isLiveMode {
                Text(L10n.agentLiveMode)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.purple.opacity(0.12), in: Capsule())
            }

            Spacer()

            Button(action: onStop) {
                Label(L10n.stopAgent, systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(L10n.stopAgent)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

/// チャット入力バー。
private struct ChatInputBar: View {
    @Binding var text: String
    var isEnabled: Bool
    let onSend: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("メッセージを入力...", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.leading, 4)
                .focused($isTextFieldFocused)
                .onSubmit(onSend)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(hasContent ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!hasContent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(capsuleInputBarBackground)
        .disabled(!isEnabled)
        .onAppear {
            guard isEnabled else { return }
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            guard enabled else { return }
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }

}

/// チャット風の吹き出しビュー。
private struct ChatBubbleView: View {
    let message: AgentMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if message.role == .toolUse {
            HStack(alignment: .top, spacing: 8) {
                Color.clear.frame(width: 28, height: 28)
                ToolUseCardView(message: message)
                Spacer(minLength: 60)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isUser {
                    Spacer(minLength: 60)
                } else {
                    avatarView
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }

                bubbleContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

                if !isUser {
                    Spacer(minLength: 60)
                }
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        switch message.role {
        case .assistant:
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
                .background(.purple.opacity(0.1), in: Circle())
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .background(.red.opacity(0.1), in: Circle())
        case .system:
            Image(systemName: "gear")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.secondary.opacity(0.1), in: Circle())
        case .user, .toolUse:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.role {
        case .assistant:
            MarkdownContentView(markdown: message.content)
        case .user:
            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        case .error:
            Text(message.content)
                .font(.body)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .system:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .toolUse:
            EmptyView()
        }
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .user: AnyShapeStyle(Color.accentColor)
        case .assistant: AnyShapeStyle(.background.secondary)
        case .error: AnyShapeStyle(Color.red.opacity(0.1))
        case .system: AnyShapeStyle(.background.tertiary)
        case .toolUse: AnyShapeStyle(.clear)
        }
    }
}

// MARK: - Tool Use Card View

/// ツール呼び出しをカード形式で表示するビュー。
private struct ToolUseCardView: View {
    let message: AgentMessage

    private var info: ToolCallInfo? { message.toolCallInfo }
    private var toolName: String { info?.toolName ?? "" }
    private var hasResult: Bool { info?.toolResult != nil }
    private var isError: Bool { info?.toolResult?.isError == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolHeader
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            // TodoWrite: チェックリスト表示
            if toolName == "TodoWrite" {
                todoWriteSection
            }

            // Edit: diff 表示
            if toolName == "Edit", let input = info?.toolInput {
                editDiffSection(input: input)
            }

            // ツール結果（omit リストに含まれないもの）
            if let result = info?.toolResult,
               !AgentService.toolsOmitResult.contains(toolName) {
                Divider()
                toolResultSection(result)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
    }

    // MARK: - Header

    private var toolHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: toolIcon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(toolName)
                .font(.caption.bold())

            if !AgentService.toolsOmitInputSummary.contains(toolName) {
                Text(message.content)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            statusIndicator
        }
    }

    private var toolIcon: String {
        switch toolName {
        case "Bash": "terminal.fill"
        case "Read": "doc.text"
        case "Write": "doc.badge.plus"
        case "Edit": "pencil"
        case "Grep": "magnifyingglass"
        case "Glob": "folder.badge.magnifyingglass"
        case "TodoWrite": "checklist"
        case "Agent": "person.2"
        case "Skill": "wand.and.stars"
        default: "wrench"
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if !hasResult {
            ProgressView()
                .controlSize(.mini)
        } else if isError {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        }
    }

    // MARK: - TodoWrite

    @ViewBuilder
    private var todoWriteSection: some View {
        if let todos = info?.toolInput["todos"] as? [[String: Any]], !todos.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                    let status = todo["status"] as? String ?? "pending"
                    let content = todo["content"] as? String ?? ""
                    HStack(spacing: 6) {
                        Image(systemName: todoStatusIcon(status))
                            .font(.system(size: 12))
                            .foregroundStyle(todoStatusColor(status))
                        Text(content)
                            .font(.caption)
                            .foregroundStyle(status == "completed" ? .secondary : .primary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func todoStatusIcon(_ status: String) -> String {
        switch status {
        case "completed": "checkmark.square.fill"
        case "in_progress": "square.dotted"
        default: "square"
        }
    }

    private func todoStatusColor(_ status: String) -> Color {
        switch status {
        case "completed": .green
        case "in_progress": .blue
        default: .secondary
        }
    }

    // MARK: - Edit Diff

    @ViewBuilder
    private func editDiffSection(input: [String: Any]) -> some View {
        let oldString = input["old_string"] as? String
        let newString = input["new_string"] as? String
        if oldString != nil || newString != nil {
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                if let old = oldString {
                    ForEach(Array(old.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        Text("- \(line)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .background(Color.red.opacity(0.08))
                    }
                }
                if let new = newString {
                    ForEach(Array(new.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        Text("+ \(line)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .background(Color.green.opacity(0.08))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Tool Result

    @ViewBuilder
    private func toolResultSection(_ result: ToolResultInfo) -> some View {
        if result.isError {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text(result.content)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        } else {
            Text(result.content.prefix(500))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Shared Input Bar Background

private var capsuleInputBarBackground: some View {
    Capsule()
        .fill(.ultraThinMaterial)
        .overlay {
            Capsule()
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}

private var askLauncherBackground: some View {
    ZStack {
        Color.clear

        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor),
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        RadialGradient(
            colors: [
                .white.opacity(0.55),
                .clear,
            ],
            center: .top,
            startRadius: 80,
            endRadius: 420
        )
        .blendMode(.plusLighter)
    }
}

private var askLauncherCardBackground: some View {
    RoundedRectangle(cornerRadius: 30)
        .fill(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(.separator.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 28, y: 16)
}

private enum AgentFloatingInputMetrics {
    static let bottomPadding: CGFloat = 24
    static let contentBottomInset: CGFloat = 102
    static let scrollBottomInset: CGFloat = 110
}

private enum AskLauncherMetrics {
    static let maxContentWidth: CGFloat = 1_140
    static let minHeight: CGFloat = 760
    static let outerPadding: CGFloat = 48
    static let topSpacing: CGFloat = 72
    static let bottomSpacing: CGFloat = 56
    static let sectionSpacing: CGFloat = 40
    static let headerSpacing: CGFloat = 16
    static let titleSize: CGFloat = 60
    static let promptSize: CGFloat = 28
    static let cardSpacing: CGFloat = 28
    static let cardPadding: CGFloat = 30
    static let suggestionSpacing: CGFloat = 18
}
