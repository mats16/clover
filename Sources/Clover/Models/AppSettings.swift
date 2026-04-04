import SwiftUI
import AppKit

/// Markdown ファイルを開くエディタの選択肢。
enum MarkdownEditor: String, CaseIterable, Identifiable {
    case system
    case obsidian
    case vscode
    case cursor
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:      return L10n.systemDefault
        case .obsidian:    return "Obsidian"
        case .vscode:      return "Visual Studio Code"
        case .cursor:      return "Cursor"
        case .antigravity: return "Antigravity"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .system:      return nil
        case .obsidian:    return "md.obsidian"
        case .vscode:      return "com.microsoft.VSCode"
        case .cursor:      return "com.todesktop.230313mzl4w4u92"
        case .antigravity: return "com.google.antigravity"
        }
    }

    var isInstalled: Bool {
        guard let bid = bundleIdentifier else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil
    }

    static var availableEditors: [MarkdownEditor] {
        allCases.filter(\.isInstalled)
    }

    func open(_ url: URL) {
        // Obsidian は file:// URL を渡してもファイルを開けないため URI スキームを使う
        if self == .obsidian {
            var components = URLComponents()
            components.scheme = "obsidian"
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "path", value: url.path)]
            if let obsidianURL = components.url {
                NSWorkspace.shared.open(obsidianURL)
                return
            }
        }

        guard let bid = bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

/// アプリ設定の一元管理。@AppStorage で UserDefaults に永続化。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - 音声認識設定
    @AppStorage("transcriptionLocale") var transcriptionLocale: String = Locale.current.identifier

    // MARK: - 表示言語設定
    /// 言語選択ピッカーに表示する言語の識別子（JSON配列）。空文字列の場合は全言語を表示。
    @AppStorage("enabledLocaleIdentifiers") var enabledLocaleIdentifiersJSON: String = ""

    var enabledLocaleIdentifiers: Set<String> {
        get {
            guard !enabledLocaleIdentifiersJSON.isEmpty,
                  let data = enabledLocaleIdentifiersJSON.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(array)
        }
        set {
            if newValue.isEmpty {
                enabledLocaleIdentifiersJSON = ""
            } else {
                let array = Array(newValue).sorted()
                if let data = try? JSONEncoder().encode(array),
                   let json = String(data: data, encoding: .utf8) {
                    enabledLocaleIdentifiersJSON = json
                }
            }
        }
    }

    /// 指定ロケールが有効かどうか。空の場合は全て有効。
    func isLocaleEnabled(_ identifier: String) -> Bool {
        let enabled = enabledLocaleIdentifiers
        return enabled.isEmpty || enabled.contains(identifier)
    }

    // MARK: - Markdown エディタ設定
    @AppStorage("markdownEditor") var markdownEditorRawValue: String = MarkdownEditor.system.rawValue

    var markdownEditor: MarkdownEditor {
        get { MarkdownEditor(rawValue: markdownEditorRawValue) ?? .system }
        set { markdownEditorRawValue = newValue.rawValue }
    }

    // MARK: - 保管庫設定
    @AppStorage("vaultPath") var vaultPath: String = AppSettings.defaultVaultPath

    nonisolated static let defaultVaultPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("Obsidian Vault")
            .path
    }()

    var vaultURL: URL {
        URL(fileURLWithPath: vaultPath, isDirectory: true)
    }

    /// 保管庫ディレクトリが存在しなければ作成する。
    func ensureVaultExists() throws {
        try FileManager.default.createDirectory(
            at: vaultURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: - LLM 設定

    @AppStorage("llmEndpointURL") var llmEndpointURL: String = ""
    @AppStorage("llmModelName") var llmModelName: String = ""
    @AppStorage("llmAutoSummaryEnabled") var llmAutoSummaryEnabled: Bool = false
    @AppStorage("llmSummaryPrompt") var llmSummaryPrompt: String = AppSettings.defaultSummaryPrompt
    @AppStorage("selectedTemplateName") var selectedTemplateName: String = "customer_meeting"

    /// プリセットテンプレート名と内容のマッピング。
    nonisolated static let presetTemplates: [String: String] = [
        "customer_meeting": defaultSummaryPrompt,
    ]

    // swiftlint:disable:next line_length
    nonisolated static let defaultSummaryPrompt: String = """
    # Role and Objective
    You are a meeting analyst. Extract a structured summary from the provided <transcript>.

    # Output Format
    Use Markdown for all output. Structure your response using the sections defined in <format>.

    <format>
    ### 次のステップ
    会話の内容に基づいて、次のステップが何かを整理してください。もし日付が出ていれば、それも含めて記載すること。

    ### 要点・決定事項
    議論の要点や決定事項を整理してください。

    ### 進捗
    進行中の案件やプロジェクトについて整理してください。前回のミーティングからの進捗や、タスクや期限の変更があれば記載します。

    ### 課題・懸念点
    ミーティング中に挙がった課題や懸念点をまとめてください。特に、フォローアップが必要な内容を重点的にリストアップします。
    </format>

    # Instructions

    <rules>
    - Output only the body of the summary
    - Make the text easy to read and avoid information overload
        - Prioritize headings and bullet points over paragraphs
        - Use checkboxes for action items
    - It is acceptable to directly quote the customer when necessary
    - Write in a casual yet professional tone
    </rules>
    """

    /// API トークン（Keychain に保存）。
    var llmAPIToken: String {
        get { KeychainService.load(key: "llmAPIToken") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainService.delete(key: "llmAPIToken")
            } else {
                do {
                    try KeychainService.save(key: "llmAPIToken", value: newValue)
                } catch {
                    print("[KeychainService] Failed to save API token: \(error)")
                }
            }
            objectWillChange.send()
        }
    }
}

// MARK: - UserDefaults KVO キーパス

extension UserDefaults {
    @objc dynamic var vaultPath: String? {
        string(forKey: "vaultPath")
    }

    @objc dynamic var enabledLocaleIdentifiersJSON: String? {
        string(forKey: "enabledLocaleIdentifiers")
    }

    @objc dynamic var llmAutoSummaryEnabled: Bool {
        bool(forKey: "llmAutoSummaryEnabled")
    }
}
