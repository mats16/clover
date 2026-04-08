import Foundation

/// 文字起こしテキストを LLM で要約し、Obsidian 互換の Markdown ファイルとして保存するサービス。
enum SummaryService {
    /// 要約を生成してプロジェクトフォルダに Markdown ファイルとして書き出す。
    /// - Returns: 生成された `.md` ファイルの URL。
    @MainActor
    static func generateSummary(
        projectURL: URL,
        transcriptionId: UUID,
        startedAt: Date,
        transcriptText: String
    ) async throws -> URL {
        let settings = AppSettings.shared
        let endpoint = settings.llmEndpointURL
        let model = settings.llmModelName
        let token = settings.llmAPIToken
        let prompt = resolvedSummaryPrompt(settings: settings)

        // メッセージ組み立て: テンプレート(system) → CONTEXT.md(user) → 文字起こし(user)
        let contextContent = readContext(in: projectURL)

        var messages: [LLMService.ChatMessage] = [
            .init(role: "system", content: prompt),
        ]
        if let contextContent {
            messages.append(.init(role: "user", content: contextContent))
        }
        messages.append(.init(
            role: "user",
            content: "<transcript_id>\(transcriptionId.uuidString)</transcript_id>\n<transcript>\n\(transcriptText)\n</transcript>"
        ))

        let summary = try await LLMService.chatCompletion(
            endpoint: endpoint,
            model: model,
            token: token,
            messages: messages,
            maxTokens: 4096
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateString = formatter.string(from: startedAt)
        // タグ: 常に transcription-summary を含め、CONTEXT.md の tags をマージ
        var tags = ["transcription-summary"]
        if let contextContent {
            for tag in parseFrontmatterTags(from: contextContent) where !tags.contains(tag) {
                tags.append(tag)
            }
        }
        let tagsYAML = tags.map { "  - \($0)" }.joined(separator: "\n")

        let frontmatter = """
        ---
        transcription_id: "\(transcriptionId.uuidString)"
        date: "\(dateString)"
        tags:
        \(tagsYAML)
        ---
        """

        let markdown = frontmatter + "\n\n" + summary + "\n"

        let fileURL = projectURL.appendingPathComponent("summary_\(transcriptionId.uuidString).md")
        try Data(markdown.utf8).write(to: fileURL, options: .atomic)

        return fileURL
    }

    /// プロジェクトフォルダ内の `.md` ファイルを走査し、frontmatter の `transcription_id` が一致するファイルを返す。
    static func findSummaryFile(in projectURL: URL, transcriptionId: UUID) -> URL? {
        let fm = FileManager.default
        let targetId = transcriptionId.uuidString.lowercased()

        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" else { continue }
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 512),
                  let head = String(data: data, encoding: .utf8) else { continue }
            // frontmatter 内の transcription_id を case-insensitive で照合
            let lowered = head.lowercased()
            if lowered.contains("transcription_id:"),
               lowered.contains(targetId) {
                return fileURL
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    /// 選択中テンプレートの内容をファイルから解決する。ファイルが見つからなければフォールバック。
    @MainActor
    private static func resolvedSummaryPrompt(settings: AppSettings) -> String {
        guard let vaultURL = settings.vaultURL else { return settings.llmSummaryPrompt }
        let templateURL = SummaryTemplateService.templatesDirectoryURL(in: vaultURL)
            .appendingPathComponent(settings.selectedTemplateName + ".md")
        if let content = try? String(contentsOf: templateURL, encoding: .utf8),
           !content.isEmpty {
            return content
        }
        return settings.llmSummaryPrompt
    }

    /// プロジェクトフォルダ直下の CONTEXT.md を読み込む。存在しないか空なら nil。
    private static func readContext(in projectURL: URL) -> String? {
        let url = projectURL.appendingPathComponent("CONTEXT.md")
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              !content.isEmpty else {
            return nil
        }
        return content
    }

    /// YAML frontmatter から tags リストを抽出する。
    private static func parseFrontmatterTags(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)

        guard let firstLine = lines.first,
              firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            return []
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            return []
        }

        let frontmatterLines = lines[1 ..< closingIndex]

        guard let tagsLineIndex = frontmatterLines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "tags:"
        }) else {
            return []
        }

        var tags: [String] = []
        for line in frontmatterLines[frontmatterLines.index(after: tagsLineIndex)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { break }
            let tag = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if !tag.isEmpty {
                tags.append(tag)
            }
        }
        return tags
    }
}
