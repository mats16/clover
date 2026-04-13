import SwiftUI

/// NavigationSplitView でサイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isAgentSidebarPresented = false
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        let controlPanel = ControlPanelView(
            viewModel: viewModel,
            sidebarViewModel: sidebarViewModel,
            isAgentSidebarPresented: $isAgentSidebarPresented
        )

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                viewModel: viewModel,
                sidebarViewModel: sidebarViewModel,
                columnVisibility: columnVisibility,
                onSelectVault: onSelectVault
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if appSettings.agentEnabled, isAgentSidebarPresented {
                HSplitView {
                    controlPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    AgentSidebarView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 480, maxHeight: .infinity)
                        .background(.background)
                }
            } else {
                controlPanel
            }
        }
        .onChange(of: viewModel.currentTranscriptionId) { oldId, newId in
            guard oldId != newId else { return }
            viewModel.resetAgentSegmentTrackingIfNeeded()
        }
        .onChange(of: appSettings.agentEnabled) { _, isEnabled in
            if !isEnabled {
                isAgentSidebarPresented = false
            }
        }
    }
}
