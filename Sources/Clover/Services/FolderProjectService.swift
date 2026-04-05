import Foundation

/// 保管庫内のプロジェクトフォルダに対するファイルシステム操作を提供する。
struct FolderProjectService {
    private let fileManager = FileManager.default

    // MARK: - CONTEXT

    /// CONTEXT.md が存在しなければ Obsidian 互換のフロントマッター付きで作成し、URL を返す。
    @discardableResult
    func ensureContextFileExists(at projectURL: URL) -> URL? {
        let url = projectURL.appendingPathComponent("CONTEXT.md")
        guard !fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let content = """
        ---
        tags:
          - customer_meeting
        ---

        # context
        This is a meeting with a customer. The goal is to understand the customer's industry, organization, project, needs, and concerns, and to follow up on that information to increase the customer's usage of the product.

        """
        do {
            try Data(content.utf8).write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
