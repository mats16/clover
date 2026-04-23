import SwiftUI

/// Markdown を行単位でパースし、ネイティブ SwiftUI ビューとしてレンダリングする。
/// WKWebView を使わないため高さの問題が発生しない。
struct MarkdownContentView: View {
    let markdown: String
    @State private var blocks: [Block] = []
    @State private var parseTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(blocks, id: \.self) { block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .onAppear {
            blocks = Self.parseBlocks(markdown)
        }
        .onDisappear {
            parseTask?.cancel()
        }
        .onChange(of: markdown) { _, newValue in
            parseTask?.cancel()
            parseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                blocks = Self.parseBlocks(newValue)
            }
        }
    }

    private enum Block: Hashable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case codeBlock(code: String)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
        case blockquote(text: String)
    }

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

    private static func parseBlocks(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.codeBlock(code: codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed.allSatisfy({ $0 == "-" || $0 == " " }), trimmed.count(where: { $0 == "-" }) >= 3 {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            if let match = trimmed.firstMatch(of: /^(#{1,3})\s+(.+)$/) {
                let level = match.1.count
                let text = String(match.2)
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            if trimmed.contains("|"),
               i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).contains("---") {
                let headers = parsePipeRow(trimmed)
                i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).contains("|") {
                    rows.append(parsePipeRow(lines[i]))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

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

    private static func parsePipeRow(_ line: String) -> [String] {
        line.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
