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
        let prompt = settings.llmSummaryPrompt

        let userContent = "<transcription>\n\(transcriptText)\n</transcription>"

        let messages: [LLMService.ChatMessage] = [
            .init(role: "system", content: prompt),
            .init(role: "user", content: userContent),
        ]

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
        let frontmatter = """
        ---
        transcription_id: "\(transcriptionId.uuidString)"
        date: "\(dateString)"
        tags:
          - transcription-summary
        ---
        """

        let markdown = frontmatter + "\n\n" + summary + "\n"

        let fileURL = projectURL.appendingPathComponent("summary_\(transcriptionId.uuidString).md")
        try Data(markdown.utf8).write(to: fileURL, options: .atomic)

        return fileURL
    }
}
