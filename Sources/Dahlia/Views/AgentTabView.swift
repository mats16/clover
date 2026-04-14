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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
               let vaultURL = sidebarViewModel.currentVault?.url {
                await viewModel.startListening(
                    dbQueue: dbQueue,
                    projectURL: projectURL,
                    projectId: project.id,
                    projectName: project.name,
                    vaultURL: vaultURL
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

// MARK: - Markdown Content View

/// Markdown を行単位でパースし、ネイティブ SwiftUI ビューとしてレンダリングする。
/// WKWebView を使わないため高さの問題が発生しない。
private struct MarkdownContentView: View {
    let markdown: String
    @State private var blocks: [Block] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .task(id: markdown) {
            blocks = Self.parseBlocks(markdown)
        }
    }

    // MARK: - Block Model

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case codeBlock(code: String)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
        case blockquote(text: String)
    }

    // MARK: - Block Views

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            headingView(level: level, text: text)
        case let .paragraph(text):
            inlineMarkdownText(text)
                .font(.body)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        inlineMarkdownText(item)
                    }
                    .font(.body)
                }
            }
            .padding(.leading, 8)
        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(idx + 1).")
                            .monospacedDigit()
                        inlineMarkdownText(item)
                    }
                    .font(.body)
                }
            }
            .padding(.leading, 8)
        case let .codeBlock(code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        case let .table(headers, rows):
            tableView(headers: headers, rows: rows)
        case let .blockquote(text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                inlineMarkdownText(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        switch level {
        case 1:
            inlineMarkdownText(text)
                .font(.title2.bold())
                .padding(.top, 6)
        case 2:
            inlineMarkdownText(text)
                .font(.title3.bold())
                .padding(.top, 4)
        default:
            inlineMarkdownText(text)
                .font(.headline)
                .padding(.top, 2)
        }
    }

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            // ヘッダー行
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06))
                }
            }
            Divider()
            // データ行
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inlineMarkdownText(cell)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
            }
        }
        .border(Color.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// インライン Markdown（太字・イタリック・コード・リンク）を AttributedString でレンダリングする。
    @ViewBuilder
    private func inlineMarkdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    // MARK: - Block Parser

    private static func parseBlocks(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行はスキップ
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // コードブロック
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // 閉じ ```
                blocks.append(.codeBlock(code: codeLines.joined(separator: "\n")))
                continue
            }

            // 水平線
            if trimmed.allSatisfy({ $0 == "-" || $0 == " " }), trimmed.count(where: { $0 == "-" }) >= 3 {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // 見出し
            if let match = trimmed.firstMatch(of: /^(#{1,3})\s+(.+)$/) {
                let level = match.1.count
                let text = String(match.2)
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            // テーブル（ヘッダー + セパレーター + データ行）
            if trimmed.contains("|"),
               i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).contains("---") {
                let headers = parsePipeRow(trimmed)
                i += 2 // ヘッダーとセパレーターをスキップ
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).contains("|") {
                    rows.append(parsePipeRow(lines[i]))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let content = lines[i].trimmingCharacters(in: .whitespaces)
                        .replacing(/^>\s?/, with: "")
                    quoteLines.append(content)
                    i += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: " ")))
                continue
            }

            // 順序なしリスト
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                        items.append(String(t.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // 順序付きリスト
            if trimmed.firstMatch(of: /^\d+\.\s+/) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let match = t.firstMatch(of: /^\d+\.\s+(.+)$/) {
                        items.append(String(match.1))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // パラグラフ（上記に該当しないもの）
            var paragraphLines: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix("---")
                    || t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("> ")
                    || t.firstMatch(of: /^\d+\.\s+/) != nil {
                    break
                }
                paragraphLines.append(t)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    /// テーブル行を `|` で分割してセルの配列にする。
    private static func parsePipeRow(_ line: String) -> [String] {
        line.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
