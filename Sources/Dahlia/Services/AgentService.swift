import Combine
import Foundation
import os

/// Agent の開始モード。
enum AgentStartMode {
    /// プロジェクトディレクトリで Claude Code を実行（transcript 入力なし）。
    case project
    /// 文字起こしを継続的に Claude Code に入力として渡す。
    case transcript(store: TranscriptStore)

    var isTranscript: Bool {
        if case .transcript = self { return true }
        return false
    }
}

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

    /// 起動時に選択されたモード。
    private(set) var mode: AgentStartMode = .project

    // MARK: - Private State

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var sentSegmentIds: Set<UUID> = []
    private var cancellable: AnyCancellable?
    private var readTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.dahlia", category: "AgentService")

    // MARK: - Lifecycle

    func start(workingDirectory: URL, mode: AgentStartMode, initialMessage: String? = nil) {
        self.mode = mode
        guard !isRunning else { return }

        let systemPrompt = switch mode {
        case .transcript:
            """
            あなたはミーティングアシスタントです。\
            ディレクトリ配下には過去の議事録が格納されています。\
            リアルタイムの文字起こしを受け取り、要点の整理や質問への回答を行ってください。\
            文字起こしは随時送られてくるため、新規の情報がない場合など、応答の必要がない場合は対応不要です。
            """
        case .project:
            """
            あなたはミーティングアシスタントです。\
            ディレクトリ配下には過去の議事録が格納されています。\
            要点の整理や質問への回答など、ユーザーの質問に回答してください。
            """
        }

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
        if case let .transcript(store) = mode {
            startObservingSegments(store: store)
        }
        if let initialMessage, !initialMessage.isEmpty {
            sendUserMessage(initialMessage)
        }
    }

    /// ユーザーが手動で入力したメッセージを送信する。
    func sendUserMessage(_ text: String) {
        guard !text.isEmpty else { return }
        messages.append(AgentMessage(role: .user, content: text))
        writeToStdin(content: text)
    }

    func stop() {
        isRunning = false
        cancellable = nil
        readTask?.cancel()

        try? stdinPipe?.fileHandleForWriting.close()

        let proc = process
        Task.detached {
            // stdin を閉じた後、プロセスの自発的終了を待つ
            try? await Task.sleep(for: .milliseconds(500))
            guard proc?.isRunning == true else { return }
            // SIGTERM を送信
            proc?.terminate()
            try? await Task.sleep(for: .seconds(2))
            if proc?.isRunning == true {
                // 応答しない場合は SIGKILL で強制終了
                kill(proc!.processIdentifier, SIGKILL)
            }
        }

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    /// transcript 切替時にセグメント追跡をリセットし、新しい store を再観測する。
    func resetSegmentTracking(store: TranscriptStore) {
        cancellable = nil
        sentSegmentIds.removeAll()
        startObservingSegments(store: store)
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
        let existingConfirmed = store.segments.filter(\.isConfirmed)
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

    /// `assistant` 確定イベントが、直前に `content_block_delta` で組み立てた本文と重複することがあるため、同一なら追加しない。
    private func isDuplicateAssistantBubble(comparedTo text: String) -> Bool {
        guard let last = messages.last, last.role == .assistant else { return false }
        return last.content.trimmingCharacters(in: .whitespacesAndNewlines)
            == text.trimmingCharacters(in: .whitespacesAndNewlines)
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
                if !text.isEmpty, !isDuplicateAssistantBubble(comparedTo: text) {
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
            // UI には `assistant` / `content_block_delta` のみ反映する（`result` はメタ用の重複になりがち）
            break
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
