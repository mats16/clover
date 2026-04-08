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
    @StateObject private var meetingDetectionService = MeetingDetectionService()
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
        meetingDetectionService.isRecording = { [weak viewModel] in viewModel?.isListening ?? false }
        let capturedDb = db
        meetingDetectionService.onStartTranscription = { [weak viewModel] in
            guard let viewModel,
                  let vault = AppSettings.shared.currentVault
            else { return }

            // "Meetings" プロジェクトを取得または自動作成
            let repo = TranscriptionRepository(dbQueue: capturedDb.dbQueue)
            let projectName = "Meetings"
            guard let project = try? repo.fetchOrCreateProject(name: projectName, vaultId: vault.id) else { return }
            let projectURL = vault.url.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

            viewModel.toggleListening(
                dbQueue: capturedDb.dbQueue,
                projectURL: projectURL,
                projectId: project.id,
                projectName: project.name,
                vaultURL: vault.url
            )
        }
        meetingDetectionService.start()
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
