import SwiftUI

/// Agent タブのコンテンツビュー。Claude Code CLI の出力をチャット風に表示する。
struct AgentTabView: View {
    @ObservedObject var viewModel: CaptionViewModel

    var body: some View {
        Group {
            if let service = viewModel.agentService {
                AgentChatView(service: service)
            } else {
                ContentUnavailableView {
                    Label(L10n.agent, systemImage: "sparkles")
                } description: {
                    if viewModel.isListening {
                        Text("Agent タブに切り替えると Claude Code が起動します")
                    } else {
                        Text("文字起こしを開始してから Agent タブに切り替えてください")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            viewModel.activateAgentIfNeeded()
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

            // 入力欄
            Divider()
            ChatInputBar(text: $inputText) {
                let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else { return }
                service.sendUserMessage(message)
                inputText = ""
            }
            .disabled(!service.isRunning)
        }
    }
}

/// チャット入力バー。
private struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("メッセージを入力...", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
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
    }
}

/// チャット風の吹き出しビュー。
private struct ChatBubbleView: View {
    let message: AgentMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                avatarView
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
        case .user:
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
        }
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .user: AnyShapeStyle(Color.accentColor)
        case .assistant: AnyShapeStyle(.background.secondary)
        case .error: AnyShapeStyle(Color.red.opacity(0.1))
        case .system: AnyShapeStyle(.background.tertiary)
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

    @ViewBuilder
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
            if trimmed.allSatisfy({ $0 == "-" || $0 == " " }), trimmed.filter({ $0 == "-" }).count >= 3 {
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
