import Foundation

/// 保管庫内の要約テンプレートファイルを管理するサービス。
struct SummaryTemplateService {
    private let fileManager = FileManager.default

    /// テンプレートディレクトリ URL: `<vault>/_summarize_templates/`
    static func templatesDirectoryURL(in vaultURL: URL) -> URL {
        vaultURL
            .appendingPathComponent("_summarize_templates", isDirectory: true)
    }

    /// テンプレートディレクトリが無ければ作成する。
    func ensureDirectoryExists(in vaultURL: URL) throws {
        let dir = Self.templatesDirectoryURL(in: vaultURL)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// ディレクトリ内の `.md` ファイル一覧を名前順で取得する。
    func fetchTemplates(in vaultURL: URL) throws -> [SummaryTemplate] {
        let dir = Self.templatesDirectoryURL(in: vaultURL)
        guard fileManager.fileExists(atPath: dir.path) else { return [] }

        let contents = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.pathExtension == "md" }
            .map { SummaryTemplate(url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// テンプレートファイルの内容を読み込む。
    func readContent(of template: SummaryTemplate) throws -> String {
        try String(contentsOf: template.url, encoding: .utf8)
    }

    /// プリセットテンプレートが存在しなければ書き出す（初回 seed 用）。
    func seedPresets(in vaultURL: URL) throws {
        try ensureDirectoryExists(in: vaultURL)
        let dir = Self.templatesDirectoryURL(in: vaultURL)

        for (name, content) in AppSettings.presetTemplates {
            let fileURL = dir.appendingPathComponent("\(name).md")
            guard !fileManager.fileExists(atPath: fileURL.path) else { continue }
            try Data(content.utf8).write(to: fileURL, options: .atomic)
        }
    }

    /// プリセットテンプレートを強制的にデフォルト内容で上書きする。
    /// ユーザーが作成したテンプレートには影響しない。
    func resetPresets(in vaultURL: URL) throws {
        try ensureDirectoryExists(in: vaultURL)
        let dir = Self.templatesDirectoryURL(in: vaultURL)

        for (name, content) in AppSettings.presetTemplates {
            let fileURL = dir.appendingPathComponent("\(name).md")
            try Data(content.utf8).write(to: fileURL, options: .atomic)
        }
    }
}
