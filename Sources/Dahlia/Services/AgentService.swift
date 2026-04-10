import Combine
import Foundation
import os

/// Claude Code CLI プロセスのメッセージロール。
enum AgentMessageRole {
    case user
    case assistant
    case system
    case error
}

/// Claude Code CLI プロセスからの出力メッセージ。
struct AgentMessage: Identifiable {
    let id: UUID = .v7()
    let role: AgentMessageRole
    var content: String
}

/// Claude Code CLI をサブプロセスとして管理し、確定済み文字起こしセグメントをストリーミングで送信するサービス。
@MainActor
final class AgentService: ObservableObject {

    // MARK: - Published State

    @Published var messages: [AgentMessage] = []
    @Published var isRunning = false

    // MARK: - Private State

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var sentSegmentIds: Set<UUID> = []
    private var cancellable: AnyCancellable?
    private var readTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.dahlia", category: "AgentService")

    // MARK: - Lifecycle

    func start(workingDirectory: URL, store: TranscriptStore) {
        guard !isRunning else { return }

        let systemPrompt = """
            あなたはミーティングアシスタントです。\
            リアルタイムの文字起こしを受け取り、要点の整理や質問への回答を行ってください。\
            日本語で応答してください。
            """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "claude",
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "bypassPermissions",
            "--no-session-persistence",
            "--model", "sonnet",
            "--system-prompt", systemPrompt,
        ]
        proc.currentDirectoryURL = workingDirectory

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }

        do {
            try proc.run()
        } catch {
            logger.error("Failed to launch claude process: \(error.localizedDescription)")
            messages.append(AgentMessage(role: .error, content: "Claude Code の起動に失敗しました: \(error.localizedDescription)"))
            return
        }

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.isRunning = true

        startReadingStdout(stdout)
        startObservingSegments(store: store)
    }

    /// ユーザーが手動で入力したメッセージを送信する。
    func sendUserMessage(_ text: String) {
        guard !text.isEmpty else { return }
        messages.append(AgentMessage(role: .user, content: text))
        writeToStdin(content: text)
    }

    func stop() {
        cancellable = nil
        readTask?.cancel()

        try? stdinPipe?.fileHandleForWriting.close()

        let proc = process
        Task.detached {
            try? await Task.sleep(for: .milliseconds(500))
            if proc?.isRunning == true {
                proc?.terminate()
            }
        }

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    // MARK: - Stdin Writing

    private func writeToStdin(content: String) {
        guard let pipe = stdinPipe else { return }

        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": content,
            ] as [String: String],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"

        let handle = pipe.fileHandleForWriting
        Task.detached {
            if let lineData = line.data(using: .utf8) {
                try? handle.write(contentsOf: lineData)
            }
        }
    }

    // MARK: - Segment Observation

    private func startObservingSegments(store: TranscriptStore) {
        let existingConfirmed = store.segments.filter { $0.isConfirmed }
        if !existingConfirmed.isEmpty {
            sendSegments(existingConfirmed)
        }

        cancellable = store.$segments
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] segments in
                guard let self else { return }
                let newConfirmed = segments.filter {
                    $0.isConfirmed && !self.sentSegmentIds.contains($0.id)
                }
                guard !newConfirmed.isEmpty else { return }
                self.sendSegments(newConfirmed)
            }
    }

    private func sendSegments(_ segments: [TranscriptSegment]) {
        let text = segments.map(\.displayText).joined(separator: "\n")
        sentSegmentIds.formUnion(Set(segments.map(\.id)))
        writeToStdin(content: "<transcript>\(text)</transcript>")
    }

    // MARK: - Stdout Reading

    private func startReadingStdout(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading

        readTask = Task.detached { [weak self] in
            var buffer = Data()

            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                while let newlineRange = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex ..< newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex ... newlineRange.lowerBound)

                    guard let line = String(data: lineData, encoding: .utf8),
                          !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                    await self?.handleOutputLine(line)
                }
            }

            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8),
               !line.trimmingCharacters(in: .whitespaces).isEmpty {
                await self?.handleOutputLine(line)
            }
        }
    }

    private func handleOutputLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            logger.debug("Failed to parse stream-json line")
            return
        }

        switch type {
        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                let text = content.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }.joined()
                if !text.isEmpty {
                    messages.append(AgentMessage(role: .assistant, content: text))
                }
            }
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String,
               !text.isEmpty {
                if let lastIndex = messages.indices.last, messages[lastIndex].role == .assistant {
                    messages[lastIndex].content += text
                } else {
                    messages.append(AgentMessage(role: .assistant, content: text))
                }
            }
        case "result":
            if let result = json["result"] as? String, !result.isEmpty {
                messages.append(AgentMessage(role: .assistant, content: result))
            }
        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String
                ?? json["error"] as? String
                ?? "Unknown error"
            messages.append(AgentMessage(role: .error, content: errorMsg))
        default:
            break
        }
    }
}
