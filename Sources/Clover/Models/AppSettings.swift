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

    // swiftlint:disable:next line_length
    nonisolated static let defaultSummaryPrompt: String = """
    以下の文字起こしを要約してください。

    <context>
    これは顧客とのミーティングです。目的は、顧客の業種、組織状況、利用中のプロジェクト、ニーズ、懸念点を把握し、適切なフォローアップにつなげることです。特に以下を重視してください。
    - お客様の実利用量を増やすための示唆を拾うこと
    - 進行中プロジェクトの進捗、課題、停滞要因を明確にすること
    - 新しいユースケースや拡張機会を見つけること
    - 担当アカウントチーム（営業、ソリューションアーキテクト）がプロアクティブに動けるよう、次の打ち手を整理すること
    </context>

    <summary_format>
    ### 次のステップ
    会話内容に基づいて、次に何を進めるべきかを簡潔に整理してください。
    日付や期限が出ている場合は必ず含めてください。
    顧客側の予定だけでなく、営業/SA 側が先回りして実施すべき内容も記載してください。

    ### 要点・決定事項
    議論の要点や決定事項を箇条書きで整理してください。特に以下を含めてください。
    - 顧客の現状や背景
    - 進行中プロジェクトの状況
    - 顧客が重視していること
    - 合意した内容、方向性、優先順位

    ### プロジェクト進捗・課題
    進行中の案件やプロジェクトについて、以下を整理してください。
    - 現在の進捗状況
    - 直近のマイルストーン
    - 課題、ボトルネック、依存関係
    - 停滞要因やリスク
      - 進捗が不明な場合は、その旨を明記してください。

    ### 利用拡大の機会
    顧客の実利用量を増やす観点で、会話から読み取れる機会を整理してください。
    - 現在利用中の領域
    - 利用が限定的な領域
    - 拡大余地がありそうなチーム、業務、ワークロード
    - 導入・活用を広げるために必要そうな支援

    ### 新規ユースケース候補
    会話の中で明示的または示唆された新しいユースケース候補を整理してください。
    まだ確定していないアイデアも、重要であれば「候補」として記載してください。

    ### アクションアイテム
    担当者が明確なものは担当者名も記載してください。
    顧客側の宿題だけでなく、営業/SA 側のアクションも分けて整理してください。

    ### 主な懸念点・未解決事項
    ミーティング中に挙がった質問や懸念点、意思決定に必要な未解決事項を整理してください。
    特に、契約前進や利用拡大の障害になりそうな内容を重点的に記載してください。
    </summary_format>

    <summary_style>
    - 読みやすさを優先し、情報過多にしない
    - パラグラフよりも見出しと箇条書きを優先する
    - アクションアイテムはチェックボックス（- [ ]）を使用する
    - カジュアルかつプロフェッショナルなトーンで書く
    - 必要に応じて短い直接引用を使ってもよい
    - 曖昧な点は断定せず、「示唆された」「可能性がある」と表現する
    </summary_style>

    <summary_rules>
    - Markdown 形式で出力する
    - 出力をコードブロック（```）で囲まない
    - 情報が会話中に出ていない場合は、推測しすぎず「明示なし」と記載する
    - 単なる議事録ではなく、次回アクションにつながる営業・SA向けサマリーにする
    - 重要度が高いものから順に記載する
    </summary_rules>
    """

    /// API トークン（Keychain に保存）。
    var llmAPIToken: String {
        get { KeychainService.load(key: "llmAPIToken") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainService.delete(key: "llmAPIToken")
            } else {
                try? KeychainService.save(key: "llmAPIToken", value: newValue)
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
