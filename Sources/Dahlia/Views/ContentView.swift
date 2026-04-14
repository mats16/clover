import SwiftUI

/// HSplitView でサイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var isAgentSidebarPresented = false
    @State private var navigationPath: [UUID] = []
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HSplitView {
            SidebarView(
                viewModel: viewModel,
                sidebarViewModel: sidebarViewModel,
                onSelectVault: onSelectVault
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

            detailArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if appSettings.agentEnabled {
                        GeometryReader { proxy in
                            // Hidden title bar windows add a top safe area inset; offset by it so the button stays in the true top-right corner.
                            agentSidebarToggle
                                .offset(y: -proxy.safeAreaInsets.top)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        }
                    }
                }
        }
        .onChange(of: sidebarViewModel.selectedMeetingId) { _, newId in
            if let newId {
                if navigationPath != [newId] {
                    navigationPath = [newId]
                }
                handleMeetingSelection(newId)
            } else if !navigationPath.isEmpty {
                navigationPath = []
                viewModel.clearCurrentMeeting()
            }
        }
        .onChange(of: navigationPath) { oldPath, newPath in
            // ユーザーが戻るボタンで一覧に戻った場合
            if oldPath.count == 1, newPath.isEmpty {
                sidebarViewModel.selectedMeetingId = nil
                sidebarViewModel.selectedMeetingIds.removeAll()
                viewModel.clearCurrentMeeting()
            }
        }
        .onChange(of: sidebarViewModel.selectedProject?.id) { _, _ in
            navigationPath = []
        }
        .onChange(of: viewModel.currentMeetingId) { oldId, newId in
            guard oldId != newId else { return }
            viewModel.resetAgentSegmentTrackingIfNeeded()
        }
        .onChange(of: appSettings.agentEnabled) { _, isEnabled in
            if !isEnabled {
                isAgentSidebarPresented = false
            }
        }
    }

    // MARK: - Detail Area

    @ViewBuilder
    private var detailArea: some View {
        if sidebarViewModel.selectedProject != nil {
            NavigationStack(path: $navigationPath) {
                MeetingListView(
                    viewModel: viewModel,
                    sidebarViewModel: sidebarViewModel,
                    onSelectMeeting: { _ in }
                )
                .navigationDestination(for: UUID.self) { _ in
                    meetingDetailView
                }
            }
        } else {
            ContentUnavailableView {
                Label(L10n.newProject, systemImage: "folder")
            } description: {
                Text("プロジェクトを選択してください")
            }
        }
    }

    private var agentSidebarToggle: some View {
        Button {
            isAgentSidebarPresented.toggle()
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13))
                .foregroundStyle(isAgentSidebarPresented ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(L10n.agent)
        .accessibilityLabel(L10n.agent)
        .padding(.top, 14)
        .padding(.trailing, 14)
    }

    @ViewBuilder
    private var meetingDetailView: some View {
        let controlPanel = ControlPanelView(
            viewModel: viewModel,
            sidebarViewModel: sidebarViewModel,
            isAgentSidebarPresented: $isAgentSidebarPresented
        )

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

    private func handleMeetingSelection(_ meetingId: UUID) {
        guard let dbQueue = sidebarViewModel.dbQueue,
              let projectURL = sidebarViewModel.selectedProjectURL,
              let project = sidebarViewModel.selectedProject,
              let vaultURL = sidebarViewModel.currentVault?.url else { return }
        viewModel.loadMeeting(
            meetingId,
            dbQueue: dbQueue,
            projectURL: projectURL,
            projectId: project.id,
            projectName: project.name,
            vaultURL: vaultURL
        )
    }
}
