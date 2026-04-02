import Foundation

/// ファイルシステム上のフォルダで表現されるプロジェクト。
struct FolderProject: Identifiable, Hashable, Sendable {
    let url: URL
    let modifiedAt: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }

    /// 指定フォルダ URL から FolderProject を生成する。
    /// フォルダの更新日時をファイル属性から取得する。
    init(url: URL) {
        self.url = url
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.modifiedAt = (attributes?[.modificationDate] as? Date) ?? Date()
    }

    init(url: URL, modifiedAt: Date) {
        self.url = url
        self.modifiedAt = modifiedAt
    }
}
