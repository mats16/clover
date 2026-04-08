import AppKit
import SwiftUI

enum WindowID {
    static let vaultManager = "vault-manager"
}

@main
struct CloverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = CaptionViewModel()
    @StateObject private var sidebarViewModel = SidebarViewModel()
    @State private var appDatabase: AppDatabaseManager?
    @State private var showVaultPicker = true

    var body: some Scene {
        WindowGroup {
            Group {
                if showVaultPicker {
                    VaultPickerView(appDatabase: appDatabase) { vault in
                        openVault(vault)
                    }
                } else {
                    ContentView(
                        viewModel: viewModel,
                        sidebarViewModel: sidebarViewModel,
                        onSelectVault: { vault in openVault(vault) }
                    )
                }
            }
            .onAppear {
                initializeApp()
            }
        }
        .windowResizability(.contentMinSize)

        Window(L10n.vault, id: WindowID.vaultManager) {
            VaultPickerView(appDatabase: appDatabase) { vault in
                openVault(vault)
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func initializeApp() {
        guard let db = try? AppDatabaseManager() else { return }
        appDatabase = db

        let repo = TranscriptionRepository(dbQueue: db.dbQueue)
        if let lastVault = try? repo.fetchLastOpenedVault() {
            openVault(lastVault)
        }
    }

    private func openVault(_ vault: VaultRecord) {
        guard let db = appDatabase else { return }

        // 録音中なら停止
        if viewModel.isListening {
            viewModel.stopListening()
        }

        // 保管庫ディレクトリが存在しなければ作成
        try? FileManager.default.createDirectory(at: vault.url, withIntermediateDirectories: true)

        AppSettings.shared.currentVault = vault
        sidebarViewModel.setAppDatabase(db)
        sidebarViewModel.updateVaultLastOpened(vault.id)
        viewModel.prepareAnalyzer()
        showVaultPicker = false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
