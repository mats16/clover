import SwiftUI
import AppKit

@main
struct TranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = CaptionViewModel()
    @StateObject private var sidebarViewModel = SidebarViewModel()

    var body: some Scene {
        WindowGroup("Transcriber") {
            ContentView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                .onAppear {
                    try? AppSettings.shared.ensureVaultExists()
                    viewModel.prepareAnalyzer()
                    sidebarViewModel.loadProjects()
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
