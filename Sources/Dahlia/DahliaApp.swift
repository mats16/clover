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
    @StateObject private var liveSubtitleOverlayService = LiveSubtitleOverlayService()
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
                        liveSubtitleOverlayService: liveSubtitleOverlayService,
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
        meetingDetectionService.onOpenMeeting = { meeting in
            handleDetectedMeeting(meeting, in: db, startTranscription: false)
        }
        meetingDetectionService.onStartTranscription = { meeting in
            handleDetectedMeeting(meeting, in: db, startTranscription: true)
        }
        meetingDetectionService.onManageNotifications = {
            SettingsNavigation.open(.general)
        }
        meetingDetectionService.start()
        showVaultPicker = false
    }

    private func handleDetectedMeeting(
        _ meeting: DetectedMeeting,
        in db: AppDatabaseManager,
        startTranscription: Bool
    ) {
        guard let vault = AppSettings.shared.currentVault else { return }
        focusMainWindow()

        if let event = meeting.calendarEvent {
            let repository = MeetingRepository(dbQueue: db.dbQueue)
            if let existingMeetingId = try? repository.fetchMeetingIdForCalendarEvent(
                platform: CalendarEventRecord.googleCalendarPlatform,
                platformId: event.platformId
            ) {
                sidebarViewModel.deselectProject()
                sidebarViewModel.selectDestination(.meetings)
                sidebarViewModel.selectMeeting(existingMeetingId)
                if startTranscription {
                    let ctx = meetingContext(for: existingMeetingId)
                    Task {
                        await viewModel.startListening(
                            dbQueue: db.dbQueue,
                            projectURL: ctx.projectURL,
                            vaultId: vault.id,
                            projectId: ctx.projectId,
                            projectName: ctx.projectName,
                            vaultURL: vault.url,
                            appendingTo: existingMeetingId
                        )
                    }
                }
                return
            }

            sidebarViewModel.deselectProject()
            sidebarViewModel.clearMeetingSelection()
            viewModel.beginDraftMeeting(
                from: event,
                dbQueue: db.dbQueue,
                vaultURL: vault.url
            )
            guard let meetingId = viewModel.materializeDraftMeeting() else { return }
            sidebarViewModel.selectDestination(.meetings)
            sidebarViewModel.selectMeeting(meetingId)
            if startTranscription {
                Task { @MainActor in
                    await viewModel.startListening(
                        dbQueue: db.dbQueue,
                        projectURL: nil,
                        vaultId: vault.id,
                        projectId: nil,
                        projectName: nil,
                        vaultURL: vault.url,
                        appendingTo: meetingId
                    )
                }
            }
            return
        }

        let ctx = sidebarViewModel.selectedProjectContext
        if ctx.projectId == nil {
            sidebarViewModel.deselectProjectKeepingMeetingSelection()
        }
        viewModel.createEmptyMeeting(
            dbQueue: db.dbQueue,
            projectURL: ctx.projectURL,
            vaultId: vault.id,
            projectId: ctx.projectId,
            name: "",
            projectName: ctx.projectName,
            vaultURL: vault.url
        )
        guard let meetingId = viewModel.currentMeetingId else { return }
        sidebarViewModel.selectDestination(.meetings)
        sidebarViewModel.selectMeeting(meetingId)
        if startTranscription {
            Task { @MainActor in
                await viewModel.startListening(
                    dbQueue: db.dbQueue,
                    projectURL: ctx.projectURL,
                    vaultId: vault.id,
                    projectId: ctx.projectId,
                    projectName: ctx.projectName,
                    vaultURL: vault.url,
                    appendingTo: meetingId
                )
            }
        }
    }

    private func meetingContext(for meetingId: UUID) -> (projectURL: URL?, projectId: UUID?, projectName: String?) {
        guard let meetingItem = sidebarViewModel.allMeetings.first(where: { $0.meetingId == meetingId }) else {
            return (nil, nil, nil)
        }

        let projectURL = meetingItem.projectName.map { sidebarViewModel.projectURL(for: $0) }
        return (projectURL, meetingItem.projectId, meetingItem.projectName)
    }

    @MainActor
    private func focusMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        let targetWindow = NSApp.windows.first { window in
            !(window is NSPanel) && window.identifier?.rawValue != WindowID.vaultManager
        } ?? NSApp.mainWindow ?? NSApp.keyWindow

        targetWindow?.orderFrontRegardless()
        targetWindow?.makeKeyAndOrderFront(nil)
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
