import SwiftUI

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
}

// MARK: - UserDefaults KVO キーパス

extension UserDefaults {
    @objc dynamic var vaultPath: String? {
        string(forKey: "vaultPath")
    }

    @objc dynamic var enabledLocaleIdentifiersJSON: String? {
        string(forKey: "enabledLocaleIdentifiers")
    }
}
