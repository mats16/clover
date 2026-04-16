import SwiftUI

/// Agent 右サイドバーのコンテンツビュー。初期チャット入力画面またはチャット UI を表示する。
struct AgentSidebarView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let service = viewModel.agentService {
                agentHeader(service: service)
                Divider()
                AgentChatView(service: service)
            } else {
                AgentLauncherView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
            }
        }
    }

    // MARK: - Agent Header

    private func agentHeader(service: AgentService) -> some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text(service.mode.isTranscript ? L10n.agentTranscriptMode : L10n.agentProjectMode)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.stopAgent()
            } label: {
                Label(L10n.stopAgent, systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(L10n.stopAgent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private var isDisabled: Bool {
        sidebarViewModel.selectedProjectURL == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.purple)
                .padding(.bottom, 8)

            Text(L10n.agent)
                .font(.headline)
                .padding(.bottom, 4)

            Text(hasContent ? L10n.agentProjectModeDescription : L10n.agentTranscriptModeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()

            Divider()
            agentLauncherInputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var agentLauncherInputBar: some View {
        HStack(spacing: 8) {
            TextField("メッセージを入力...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.leading, 4)
                .focused($isTextFieldFocused)
                .onSubmit {
                    guard hasContent else { return }
                    launchProjectMode()
                }

            Button {
                if hasContent {
                    launchProjectMode()
                } else {
                    launchTranscriptMode()
                }
            } label: {
                Image(systemName: hasContent ? "arrow.up.circle.fill" : "waveform.badge.microphone")
                    .font(.system(size: 22))
                    .foregroundStyle(hasContent ? Color.accentColor : .purple)
            }
            .buttonStyle(.plain)
            .help(hasContent ? L10n.agentProjectMode : L10n.agentTranscriptMode)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(capsuleInputBarBackground)
        .disabled(isDisabled)
        .onAppear {
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }

    private func launchProjectMode() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        viewModel.startAgent(mode: .project, initialMessage: message, workingDirectory: sidebarViewModel.selectedProjectURL)
        inputText = ""
    }

    private func launchTranscriptMode() {
        Task {
            // 録音中でなければ文字起こしも同時に開始する
            if !viewModel.isListening,
               let dbQueue = sidebarViewModel.dbQueue,
               let projectURL = sidebarViewModel.selectedProjectURL,
               let project = sidebarViewModel.selectedProject,
               let vault = sidebarViewModel.currentVault {
                await viewModel.startListening(
                    dbQueue: dbQueue,
                    projectURL: projectURL,
                    vaultId: vault.id,
                    projectId: project.id,
                    projectName: project.name,
                    vaultURL: vault.url
                )
            }

            viewModel.startAgent(
                mode: .transcript(store: viewModel.store),
                initialMessage: "文字起こしモードを開始します。リアルタイムの文字起こしが随時送信されます。準備ができたら教えてください。",
                workingDirectory: sidebarViewModel.selectedProjectURL
            )
        }
    }
}

/// AgentService を直接 @ObservedObject で監視するチャットビュー。
private struct AgentChatView: View {
    @ObservedObject var service: AgentService
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
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
                        .padding(12)
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

            // 入力欄（インスペクター内では初回フォーカスが当たらないことがあるため明示的にフォーカスする）
            Divider()
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
        .fill(.quaternary.opacity(0.8))
        .overlay {
            Capsule()
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}
