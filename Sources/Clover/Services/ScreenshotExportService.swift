import Foundation

/// スクリーンショットを Vault の `_screenshots/` フォルダに書き出すサービス。
enum ScreenshotExportService {
    static func screenshotsDirectoryURL(in vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent("_screenshots", isDirectory: true)
    }

    /// スクリーンショットを `<vault>/_screenshots/<screenshotId>.{webp,jpeg}` に書き出す。
    /// DB の `imageData` をそのまま書き出す。
    /// - Returns: vault 相対パスの配列
    static func exportScreenshots(
        vaultURL: URL,
        screenshots: [ScreenshotRecord]
    ) throws -> [String] {
        guard !screenshots.isEmpty else { return [] }

        let dir = screenshotsDirectoryURL(in: vaultURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ext = ImageEncoder.supportsWebP ? "webp" : "jpeg"
        var relativePaths: [String] = []

        for screenshot in screenshots {
            let filename = "\(screenshot.id.uuidString).\(ext)"
            let relativePath = "_screenshots/\(filename)"
            let fileURL = vaultURL.appendingPathComponent(relativePath)
            try screenshot.imageData.write(to: fileURL, options: .atomic)
            relativePaths.append(relativePath)
        }

        return relativePaths
    }
}
