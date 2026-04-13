import SwiftUI

/// NavigationSplitView でサイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented = false
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                viewModel: viewModel,
                sidebarViewModel: sidebarViewModel,
                columnVisibility: columnVisibility,
                onSelectVault: onSelectVault
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            ControlPanelView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
        }
        .inspector(isPresented: $isInspectorPresented) {
            AgentSidebarView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.currentTranscriptionId != nil {
                    Button(L10n.export, systemImage: "square.and.arrow.up") {
                        viewModel.exportTranscript()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(viewModel.store.segments.isEmpty)
                    .help(L10n.export)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if appSettings.agentEnabled {
                    let isAgentRunning = viewModel.agentService?.isRunning == true
                    Button {
                        isInspectorPresented.toggle()
                    } label: {
                        Label(L10n.agent, systemImage: "sparkles")
                            .foregroundStyle(isAgentRunning ? .purple : .secondary)
                    }
                    .help(L10n.agent)
                }
            }
        }
        .onChange(of: viewModel.currentTranscriptionId) { oldId, newId in
            guard oldId != newId else { return }
            viewModel.resetAgentSegmentTrackingIfNeeded()
        }
    }
}
