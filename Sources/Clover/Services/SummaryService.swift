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
        transcriptText: String,
        screenshots: [ScreenshotRecord] = []
    ) async throws -> URL {
        let settings = AppSettings.shared
        let endpoint = settings.llmEndpointURL
        let model = settings.llmModelName
        let token = settings.llmAPIToken
        let prompt = resolvedSummaryPrompt(settings: settings)
        let languageName = settings.llmSummaryLanguage.displayName

        // メッセージ組み立て: テンプレート(system) → CONTEXT.md(user) → 文字起こし(user) + スクリーンショット
        let contextContent = readContext(in: projectURL)

        let systemPrompt = prompt + "\n\n# Language\nWrite the summary in \(languageName)."
        var messages: [LLMService.ChatMessage] = [
            .init(role: "system", content: systemPrompt),
        ]
        if let contextContent {
            messages.append(.init(role: "user", content: contextContent))
        }

        let transcriptContent = "<transcript_id>\(transcriptionId.uuidString)</transcript_id>\n<transcript>\n\(transcriptText)\n</transcript>"

        if screenshots.isEmpty {
            messages.append(.init(role: "user", content: transcriptContent))
        } else {
            // マルチモーダル: テキスト + スクリーンショット画像（MainActor 外でリサイズ・エンコード）
            let dataURIs = await Task.detached(priority: .userInitiated) {
                let mimeType = ImageEncoder.preferredMIMEType
                return screenshots.map { screenshot in
                    let imageData = ImageEncoder.resized(screenshot.imageData, maxLongEdge: 1024)
                    return "data:\(mimeType);base64,\(imageData.base64EncodedString())"
                }
            }.value
            var parts: [LLMService.ContentPart] = [.text(transcriptContent)]
            for dataURI in dataURIs {
                parts.append(.imageURL(dataURI))
            }
            messages.append(.init(role: "user", parts: parts))
        }

        let summary = try await LLMService.chatCompletion(
            endpoint: endpoint,
            model: model,
            token: token,
            messages: messages,
            maxTokens: 16000
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateString = formatter.string(from: startedAt)
        // タグ: 常に ai_summary を含め、CONTEXT.md の tags をマージ
        var tags = ["ai_summary"]
        if let contextContent {
            for tag in parseFrontmatterTags(from: contextContent) where !tags.contains(tag) {
                tags.append(tag)
            }
        }
        let tagsYAML = tags.map { "  - \($0)" }.joined(separator: "\n")

        let frontmatter = """
        ---
        transcript_id: "\(transcriptionId.uuidString)"
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
            // frontmatter 内の transcript_id を case-insensitive で照合
            let lowered = head.lowercased()
            if lowered.contains("transcript_id:"),
               lowered.contains(targetId) {
                return fileURL
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    /// 選択中テンプレートの内容をファイルから解決する。
    /// Auto モード時はデフォルトプロンプト全体を返す。
    /// テンプレート選択時は preamble + テンプレート内容（Output Format セクション）を結合して返す。
    @MainActor
    private static func resolvedSummaryPrompt(settings: AppSettings) -> String {
        let preamble = AppSettings.summaryPromptPreamble

        // Auto モード
        guard settings.selectedTemplateName != AppSettings.autoTemplateName else {
            return preamble + "\n\n" + AppSettings.defaultOutputFormat
        }

        // カスタムテンプレート: ファイルから Output Format セクションを読み込む
        if let vaultURL = settings.vaultURL {
            let templateURL = SummaryTemplateService.templatesDirectoryURL(in: vaultURL)
                .appendingPathComponent(settings.selectedTemplateName + ".md")
            if let content = try? String(contentsOf: templateURL, encoding: .utf8),
               !content.isEmpty {
                return preamble + "\n\n" + content
            }
        }

        // フォールバック: デフォルト
        return preamble + "\n\n" + AppSettings.defaultOutputFormat
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
