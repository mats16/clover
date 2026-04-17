import AppKit
import SwiftUI

enum WindowID {
    static let vaultManager = "vault-manager"
}

@main
struct DahliaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = CaptionViewModel()
    @State private var sidebarViewModel = SidebarViewModel()
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
            .task {
                initializeAppIfNeeded()
                await GoogleCalendarStore.shared.restoreSessionIfNeeded()
            }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Window(L10n.vault, id: WindowID.vaultManager) {
            VaultPickerView(appDatabase: appDatabase) { vault in
                openVault(vault)
            }
        }
        .windowStyle(.automatic)

        Settings {
            SettingsView()
        }
    }

    private func initializeAppIfNeeded() {
        guard appDatabase == nil else { return }
        guard let db = try? AppDatabaseManager() else { return }
        appDatabase = db

        let repo = MeetingRepository(dbQueue: db.dbQueue)
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
        let capturedSidebarViewModel = sidebarViewModel
        meetingDetectionService.onStartTranscription = { [weak viewModel] in
            guard let viewModel,
                  let vault = AppSettings.shared.currentVault
            else { return }

            let ctx = capturedSidebarViewModel.selectedProjectContext

            viewModel.toggleListening(
                dbQueue: capturedDb.dbQueue,
                projectURL: ctx.projectURL,
                vaultId: vault.id,
                projectId: ctx.projectId,
                projectName: ctx.projectName,
                vaultURL: vault.url
            )
        }
        meetingDetectionService.start()
        showVaultPicker = false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        ErrorReportingService.start()
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
