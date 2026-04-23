import Combine
import Foundation
import os

/// Agent の開始モード。
enum AgentStartMode {
    /// プロジェクトディレクトリで Agent CLI を実行（transcript 入力なし）。
    case project
    /// 文字起こしを継続的に Agent CLI に入力として渡す。
    case transcript(store: TranscriptStore)

    var isTranscript: Bool {
        if case .transcript = self { return true }
        return false
    }
}

/// Agent CLI プロセスのメッセージロール。
enum AgentMessageRole {
    case user
    case assistant
    case system
    case error
    case toolUse
}

/// ツール実行結果の情報。
struct ToolResultInfo {
    let content: String
    let isError: Bool
}

/// ツール呼び出しの詳細情報。
/// `@unchecked Sendable`: toolInput の `[String: Any]` は JSONSerialization 由来の不変値型のみ含む。
struct ToolCallInfo: @unchecked Sendable {
    let toolName: String
    let toolUseId: String
    let toolInput: [String: Any]
    var toolResult: ToolResultInfo?
}

/// Agent CLI プロセスからの出力メッセージ。
struct AgentMessage: Identifiable, @unchecked Sendable {
    let id: UUID = .v7()
    let role: AgentMessageRole
    var content: String
    var toolCallInfo: ToolCallInfo?
}

struct AgentLaunchConfiguration {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let displayName: String
}

enum AgentLaunchError: LocalizedError {
    case executableNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(command):
            "\(command) を起動できません。PATH 上の実行ファイルかフルパスを指定してください。shell alias / function は未対応です。"
        }
    }
}

enum AgentCrashError: LocalizedError {
    case unexpectedSignal(Int32)
    case abnormalExit(Int32)

    var errorDescription: String? {
        switch self {
        case let .unexpectedSignal(signal):
            "Agent が予期せず終了しました (signal \(signal))"
        case let .abnormalExit(code):
            "Agent が異常終了しました (exit code \(code))"
        }
    }
}

/// Agent CLI をサブプロセスとして管理し、確定済み文字起こしセグメントをストリーミングで送信するサービス。
@MainActor
final class AgentService: ObservableObject {

    // MARK: - Published State

    @Published var messages: [AgentMessage] = []
    @Published var isRunning = false
    @Published var isProcessing = false

    /// 起動時に選択されたモード。
    private(set) var mode: AgentStartMode = .project
    private(set) var workingDirectoryURL: URL?

    // MARK: - Private State

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var sentSegmentIds: Set<UUID> = []
    private var cancellable: AnyCancellable?
    private var readTask: Task<Void, Never>?

    /// content_block_delta のスロットリング用バッファ。
    private var pendingDeltaText = ""
    private var deltaFlushTask: Task<Void, Never>?

    /// toolUseId → messages 配列インデックスの O(1) ルックアップ。
    private var toolUseIndexByToolId: [String: Int] = [:]

    private let logger = Logger(subsystem: "com.dahlia", category: "AgentService")

    /// 結果を UI に表示しないツール。
    static let toolsOmitResult: Set = ["Glob", "Grep", "Read", "Write", "Edit", "TodoWrite"]
    /// 入力サマリーを省略するツール。
    nonisolated static let toolsOmitInputSummary: Set = ["TodoWrite"]
    nonisolated static let defaultLaunchCommand = AppSettings.defaultAgentLaunchCommand
    nonisolated static let defaultAllowedTools = "Read(/*) Glob(/*) Grep(/*) TodoWrite WebSearch WebFetch"

    // MARK: - Lifecycle

    func start(workingDirectory: URL, mode: AgentStartMode, initialMessage: String? = nil) {
        self.mode = mode
        self.workingDirectoryURL = workingDirectory
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

        let launchConfiguration: AgentLaunchConfiguration
        do {
            launchConfiguration = try Self.resolveLaunchConfiguration(
                from: AppSettings.shared.agentLaunchCommand,
                workingDirectory: workingDirectory
            )
        } catch {
            logger.error("Failed to resolve agent process: \(error.localizedDescription)")
            ErrorReportingService.capture(error, context: ["source": "agentProcessLaunchResolve"])
            messages.append(AgentMessage(role: .error, content: error.localizedDescription))
            return
        }

        let proc = Process()
        proc.executableURL = launchConfiguration.executableURL
        proc.arguments = launchConfiguration.arguments + Self.sessionArguments(
            systemPrompt: systemPrompt,
            permissionMode: AppSettings.shared.agentPermissionMode,
            allowedTools: AppSettings.shared.agentAllowedTools
        )
        proc.environment = launchConfiguration.environment
        proc.currentDirectoryURL = workingDirectory

        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] terminatedProcess in
            let reason = terminatedProcess.terminationReason
            let status = terminatedProcess.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cancellable = nil
                try? self.stdinPipe?.fileHandleForWriting.close()
                self.stdinPipe = nil
                self.readTask?.cancel()
                self.isRunning = false
                self.isProcessing = false
                self.flushPendingDelta()

                if reason == .uncaughtSignal {
                    let error = AgentCrashError.unexpectedSignal(status)
                    self.messages.append(AgentMessage(role: .error, content: error.localizedDescription))
                    self.logger.error("\(error.localizedDescription)")
                    ErrorReportingService.capture(
                        error,
                        context: ["source": "agentProcessCrash", "signal": "\(status)"]
                    )
                } else if status != 0 {
                    let error = AgentCrashError.abnormalExit(status)
                    self.messages.append(AgentMessage(role: .error, content: error.localizedDescription))
                    self.logger.warning("\(error.localizedDescription)")
                }
            }
        }

        do {
            try proc.run()
        } catch {
            logger.error("Failed to launch agent process (\(launchConfiguration.displayName)): \(error.localizedDescription)")
            ErrorReportingService.capture(error, context: ["source": "agentProcessLaunch"])
            messages.append(AgentMessage(role: .error, content: "\(launchConfiguration.displayName) の起動に失敗しました: \(error.localizedDescription)"))
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
        isProcessing = false
        cancellable = nil
        readTask?.cancel()
        flushPendingDelta()
        toolUseIndexByToolId.removeAll()

        try? stdinPipe?.fileHandleForWriting.close()

        let proc = process
        Task.detached {
            // stdin を閉じた後、プロセスの自発的終了を待つ
            try? await Task.sleep(for: .milliseconds(500))
            guard proc?.isRunning == true else { return }
            // SIGTERM を送信
            proc?.terminate()
            try? await Task.sleep(for: .seconds(2))
            if let proc, proc.isRunning {
                // 応答しない場合は SIGKILL で強制終了
                kill(proc.processIdentifier, SIGKILL)
            }
        }

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        workingDirectoryURL = nil
    }

    /// transcript 切替時にセグメント追跡をリセットし、新しい store を再観測する。
    func resetSegmentTracking(store: TranscriptStore) {
        cancellable = nil
        sentSegmentIds.removeAll()
        startObservingSegments(store: store)
    }

    // MARK: - Stdin Writing

    private func writeToStdin(content: String) {
        guard isRunning, let pipe = stdinPipe else { return }

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

    // MARK: - Parsed Event (nonisolated)

    /// stdout 行をメインスレッド外でパースした結果。
    /// `@unchecked Sendable`: toolInput の `[String: Any]` は JSONSerialization 由来の不変値型のみ含む。
    enum ParsedEvent: @unchecked Sendable {
        case assistantText(String)
        case assistantToolUses(text: String, toolUses: [(name: String, id: String, input: [String: Any], summary: String)])
        case contentBlockDelta(String)
        case toolResults([(toolUseId: String, content: String, isError: Bool)])
        case systemInit
        case result
        case error(String)
    }

    /// stdout の JSON 行をパースし、型付きイベントを返す。メインスレッド外で呼び出す。
    nonisolated static func parseOutputLine(_ line: String) -> ParsedEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            let text = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined()
            var toolUses: [(name: String, id: String, input: [String: Any], summary: String)] = []
            for block in content where block["type"] as? String == "tool_use" {
                guard let toolName = block["name"] as? String,
                      let toolUseId = block["id"] as? String else { continue }
                let toolInput = block["input"] as? [String: Any] ?? [:]
                let summary = toolInputSummary(toolName: toolName, input: toolInput)
                toolUses.append((name: toolName, id: toolUseId, input: toolInput, summary: summary))
            }
            if !text.isEmpty, toolUses.isEmpty {
                return .assistantText(text)
            }
            if !toolUses.isEmpty {
                return .assistantToolUses(text: text, toolUses: toolUses)
            }
            return text.isEmpty ? nil : .assistantText(text)
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String,
                  !text.isEmpty else { return nil }
            return .contentBlockDelta(text)
        case "user":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            var results: [(toolUseId: String, content: String, isError: Bool)] = []
            for block in content where block["type"] as? String == "tool_result" {
                guard let toolUseId = block["tool_use_id"] as? String else { continue }
                let resultContent = (block["content"] as? String) ?? ""
                let isError = block["is_error"] as? Bool ?? false
                results.append((toolUseId: toolUseId, content: resultContent, isError: isError))
            }
            return results.isEmpty ? nil : .toolResults(results)
        case "system":
            if let subtype = json["subtype"] as? String, subtype == "init" {
                return .systemInit
            }
            return nil
        case "result":
            return .result
        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String
                ?? json["error"] as? String
                ?? "Unknown error"
            return .error(errorMsg)
        default:
            return nil
        }
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

                    if let event = AgentService.parseOutputLine(line) {
                        await self?.applyEvent(event)
                    }
                }
            }

            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8),
               !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if let event = AgentService.parseOutputLine(line) {
                    await self?.applyEvent(event)
                }
            }
        }
    }

    // MARK: - Apply Event (@MainActor)

    /// `assistant` 確定イベントが、直前に `content_block_delta` で組み立てた本文と重複することがあるため、同一なら追加しない。
    private func isDuplicateAssistantBubble(comparedTo text: String) -> Bool {
        guard let last = messages.last, last.role == .assistant else { return false }
        return last.content.trimmingCharacters(in: .whitespacesAndNewlines)
            == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// パース済みイベントを @MainActor 上で状態に適用する。
    private func applyEvent(_ event: ParsedEvent) {
        switch event {
        case let .assistantText(text):
            flushPendingDelta()
            if !text.isEmpty, !isDuplicateAssistantBubble(comparedTo: text) {
                messages.append(AgentMessage(role: .assistant, content: text))
            }
        case let .assistantToolUses(text, toolUses):
            flushPendingDelta()
            if !text.isEmpty, !isDuplicateAssistantBubble(comparedTo: text) {
                messages.append(AgentMessage(role: .assistant, content: text))
            }
            for toolUse in toolUses {
                if toolUseIndexByToolId[toolUse.id] != nil { continue }
                let info = ToolCallInfo(toolName: toolUse.name, toolUseId: toolUse.id, toolInput: toolUse.input)
                messages.append(AgentMessage(role: .toolUse, content: toolUse.summary, toolCallInfo: info))
                toolUseIndexByToolId[toolUse.id] = messages.count - 1
            }
        case let .contentBlockDelta(text):
            // 最初のデルタで assistant メッセージがなければ即座に追加
            if messages.last?.role != .assistant, pendingDeltaText.isEmpty {
                messages.append(AgentMessage(role: .assistant, content: text))
                return
            }
            pendingDeltaText += text
            if deltaFlushTask == nil {
                deltaFlushTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    self?.flushPendingDelta()
                }
            }
        case let .toolResults(results):
            for result in results {
                if let idx = toolUseIndexByToolId[result.toolUseId] {
                    messages[idx].toolCallInfo?.toolResult = ToolResultInfo(
                        content: result.content,
                        isError: result.isError
                    )
                }
            }
        case .systemInit:
            isProcessing = true
        case .result:
            flushPendingDelta()
            isProcessing = false
        case let .error(errorMsg):
            flushPendingDelta()
            messages.append(AgentMessage(role: .error, content: errorMsg))
        }
    }

    /// バッファされたデルタテキストを messages に反映する。
    private func flushPendingDelta() {
        deltaFlushTask?.cancel()
        deltaFlushTask = nil
        guard !pendingDeltaText.isEmpty else { return }
        if let lastIndex = messages.indices.last, messages[lastIndex].role == .assistant {
            messages[lastIndex].content += pendingDeltaText
        } else {
            messages.append(AgentMessage(role: .assistant, content: pendingDeltaText))
        }
        pendingDeltaText = ""
    }

    // MARK: - Tool Input Summary

    /// ツール名と入力パラメータから人間可読なサマリー文字列を返す。
    nonisolated static func toolInputSummary(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return (input["command"] as? String) ?? toolName
        case "Read", "Write", "Edit":
            return (input["file_path"] as? String) ?? toolName
        case "Grep", "Glob":
            return (input["pattern"] as? String) ?? toolName
        case "WebSearch":
            return (input["query"] as? String) ?? toolName
        case "WebFetch":
            return (input["url"] as? String) ?? toolName
        case "Agent":
            return (input["subagent_type"] as? String) ?? toolName
        case "Skill":
            return (input["skill"] as? String) ?? toolName
        default:
            if toolsOmitInputSummary.contains(toolName) { return toolName }
            if let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return String(str.prefix(120))
            }
            return toolName
        }
    }

    nonisolated static func resolveLaunchArguments(from configuredCommand: String) -> [String] {
        let arguments = parseCommandLine(configuredCommand)

        return arguments.isEmpty ? [defaultLaunchCommand] : arguments
    }

    nonisolated static func resolveLaunchConfiguration(
        from configuredCommand: String,
        workingDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> AgentLaunchConfiguration {
        let arguments = resolveLaunchArguments(from: configuredCommand)
        let executableURL = try resolveExecutableURL(
            for: arguments[0],
            workingDirectory: workingDirectory,
            environment: environment,
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )

        return AgentLaunchConfiguration(
            executableURL: executableURL,
            arguments: Array(arguments.dropFirst()),
            environment: launchEnvironment(
                baseEnvironment: environment,
                homeDirectoryURL: homeDirectoryURL
            ),
            displayName: arguments.joined(separator: " ")
        )
    }

    nonisolated static func sessionArguments(
        systemPrompt: String,
        permissionMode: AgentPermissionMode,
        allowedTools: String
    ) -> [String] {
        let resolvedAllowedTools = allowedTools.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultAllowedTools
            : allowedTools

        return [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", permissionMode.rawValue,
            "--allowedTools", resolvedAllowedTools,
            "--no-session-persistence",
            "--model", "sonnet",
            "--system-prompt", systemPrompt,
        ]
    }

    nonisolated static func parseCommandLine(_ command: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var isEscaping = false
        var isInsideSingleQuotes = false
        var isInsideDoubleQuotes = false
        var hasTokenContent = false

        for character in command {
            if isEscaping {
                current.append(character)
                hasTokenContent = true
                isEscaping = false
                continue
            }

            switch character {
            case "\\":
                if isInsideSingleQuotes {
                    current.append(character)
                    hasTokenContent = true
                } else {
                    isEscaping = true
                }
            case "'":
                if isInsideDoubleQuotes {
                    current.append(character)
                    hasTokenContent = true
                } else {
                    isInsideSingleQuotes.toggle()
                    hasTokenContent = true
                }
            case "\"":
                if isInsideSingleQuotes {
                    current.append(character)
                    hasTokenContent = true
                } else {
                    isInsideDoubleQuotes.toggle()
                    hasTokenContent = true
                }
            case _ where character.isWhitespace && !isInsideSingleQuotes && !isInsideDoubleQuotes:
                if hasTokenContent {
                    arguments.append(current)
                    current = ""
                    hasTokenContent = false
                }
            default:
                current.append(character)
                hasTokenContent = true
            }
        }

        if isEscaping {
            current.append("\\")
            hasTokenContent = true
        }

        if hasTokenContent {
            arguments.append(current)
        }

        return arguments
    }

    nonisolated static func resolveExecutableURL(
        for command: String,
        workingDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        let expandedCommand = NSString(string: command).expandingTildeInPath

        if command.contains("/") {
            let explicitURL = URL(fileURLWithPath: expandedCommand, relativeTo: command.hasPrefix("/") ? nil : workingDirectory)
                .standardizedFileURL
            guard fileManager.isExecutableFile(atPath: explicitURL.path) else {
                throw AgentLaunchError.executableNotFound(command)
            }
            return explicitURL
        }

        for directory in executableSearchDirectories(
            environment: environment,
            homeDirectoryURL: homeDirectoryURL
        ) {
            let candidateURL = directory.appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        throw AgentLaunchError.executableNotFound(command)
    }

    nonisolated static func launchEnvironment(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PATH"] = executableSearchDirectories(
            environment: baseEnvironment,
            homeDirectoryURL: homeDirectoryURL
        )
        .map(\.path)
        .joined(separator: ":")
        return environment
    }

    nonisolated static func executableSearchDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let defaultDirectories = [
            homeDirectoryURL.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
        ]
        let inheritedDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }

        var seenPaths: Set<String> = []
        return (defaultDirectories + inheritedDirectories).filter { directory in
            seenPaths.insert(directory.standardizedFileURL.path).inserted
        }
    }
}
