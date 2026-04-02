import Foundation

/// 保管庫内のプロジェクトフォルダに対するファイルシステム操作を提供する。
struct FolderProjectService {
    private let fileManager = FileManager.default

    /// 保管庫内のすべてのプロジェクト（サブディレクトリ）を取得する。
    /// 更新日時の降順でソートされる。
    func fetchAllProjects(in vaultURL: URL) throws -> [FolderProject] {
        let contents = try fileManager.contentsOfDirectory(
            at: vaultURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let projects = contents.compactMap { url -> FolderProject? in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  values.isDirectory == true else {
                return nil
            }
            let modifiedAt = values.contentModificationDate ?? Date()
            return FolderProject(url: url, modifiedAt: modifiedAt)
        }

        return projects.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// 新しいプロジェクトフォルダを作成する。
    @discardableResult
    func createProject(named name: String, in vaultURL: URL) throws -> FolderProject {
        let projectURL = vaultURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: false)
        return FolderProject(url: projectURL)
    }

    /// プロジェクトフォルダの名前を変更する。
    @discardableResult
    func renameProject(_ project: FolderProject, to newName: String) throws -> FolderProject {
        let newURL = project.url.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: true)
        try fileManager.moveItem(at: project.url, to: newURL)
        return FolderProject(url: newURL)
    }

    /// プロジェクトフォルダをゴミ箱に移動する。
    func deleteProject(_ project: FolderProject) throws {
        try fileManager.trashItem(at: project.url, resultingItemURL: nil)
    }

    // MARK: - README

    /// README.md が存在しなければ Obsidian 互換のフロントマッター付きで作成し、URL を返す。
    @discardableResult
    func ensureReadmeExists(for project: FolderProject) throws -> URL {
        let url = project.url.appendingPathComponent("README.md")
        guard !fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let content = """
        ---
        tags:
          - project
        ---

        # \(project.name)

        """
        try Data(content.utf8).write(to: url)
        return url
    }
}
