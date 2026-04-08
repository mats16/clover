import SwiftUI

/// NavigationSplitView でサイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
    }
}
