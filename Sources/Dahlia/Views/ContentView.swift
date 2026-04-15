import SwiftUI

/// HSplitView でサイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var isAgentSidebarPresented = false
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HSplitView {
            SidebarView(
                sidebarViewModel: sidebarViewModel,
                onSelectVault: onSelectVault,
                onStartNewMeeting: startNewMeeting,
                isNewMeetingDisabled: !viewModel.analyzerReady
                    || sidebarViewModel.currentVault == nil
                    || viewModel.isListening
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

            detailArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if appSettings.agentEnabled, sidebarViewModel.selectedDestination != .ask {
                        GeometryReader { proxy in
                            // Hidden title bar windows add a top safe area inset; offset by it so the button stays in the true top-right corner.
                            agentSidebarToggle
                                .offset(y: -proxy.safeAreaInsets.top)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if shouldShowBottomOverlayBar {
                        HStack(spacing: 12) {
                            if shouldShowFloatingActionBar {
                                FloatingActionBar(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                            }

                            if shouldShowBatchSelectionBar {
                                BatchSelectionBar(
                                    selectedCount: sidebarViewModel.selectedMeetingIds.count,
                                    onClearSelection: {
                                        sidebarViewModel.clearMeetingSelection()
                                    },
                                    onDelete: {
                                        sidebarViewModel.deleteMeetings(ids: sidebarViewModel.selectedMeetingIds)
                                    }
                                )
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
        }
        .onChange(of: sidebarViewModel.selectedMeetingId) { oldId, newId in
            guard oldId != newId else { return }
            if let newId {
                handleMeetingSelection(newId)
            } else {
                viewModel.clearCurrentMeeting()
            }
        }
        .onChange(of: sidebarViewModel.selectedDestination) { oldValue, newValue in
            if oldValue != .meetings, newValue == .meetings {
                sidebarViewModel.clearMeetingSelection()
            }
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
        switch sidebarViewModel.selectedDestination {
        case .home:
            placeholderView(
                title: L10n.home,
                systemImage: SidebarDestination.home.systemImage,
                message: L10n.homeUnderConstruction
            )
        case .meetings:
            meetingsOverviewContent
        case .projects:
            projectsWorkspaceContent
        case .actionItems:
            placeholderView(
                title: L10n.actionItems,
                systemImage: SidebarDestination.actionItems.systemImage,
                message: L10n.actionItemsComingSoon
            )
        case .ask:
            askWorkspaceContent
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

    private var shouldShowFloatingActionBar: Bool {
        viewModel.isListening || isShowingMeetingDetail
    }

    private var shouldShowBatchSelectionBar: Bool {
        sidebarViewModel.selectedDestination == .meetings
            && sidebarViewModel.selectedMeetingId == nil
            && !sidebarViewModel.selectedMeetingIds.isEmpty
    }

    private var shouldShowBottomOverlayBar: Bool {
        shouldShowFloatingActionBar || shouldShowBatchSelectionBar
    }

    private var isShowingMeetingDetail: Bool {
        switch sidebarViewModel.selectedDestination {
        case .meetings, .projects:
            sidebarViewModel.selectedMeetingId != nil
        case .home, .actionItems, .ask:
            false
        }
    }

    @ViewBuilder
    private var meetingDetailView: some View {
        let controlPanel = ControlPanelView(
            viewModel: viewModel,
            sidebarViewModel: sidebarViewModel
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

    private var projectsWorkspaceContent: some View {
        HSplitView {
            ProjectBrowserView(sidebarViewModel: sidebarViewModel)
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)

            meetingsWorkspaceContent
        }
    }

    private var meetingsOverviewContent: some View {
        meetingDetailOrList {
            MeetingsOverviewView(
                viewModel: viewModel,
                sidebarViewModel: sidebarViewModel,
                onSelectMeeting: { _ in }
            )
        }
    }

    @ViewBuilder
    private var meetingsWorkspaceContent: some View {
        if sidebarViewModel.selectedProject == nil {
            placeholderView(
                title: L10n.meetings,
                systemImage: SidebarDestination.meetings.systemImage,
                message: L10n.selectProjectFromProjects,
                actionTitle: L10n.openProjects
            ) {
                sidebarViewModel.selectedDestination = .projects
            }
        } else {
            meetingDetailOrList {
                MeetingListView(
                    viewModel: viewModel,
                    sidebarViewModel: sidebarViewModel,
                    onSelectMeeting: { _ in }
                )
            }
        }
    }

    @ViewBuilder
    private var askWorkspaceContent: some View {
        if appSettings.agentEnabled {
            AgentSidebarView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholderView(
                title: L10n.ask,
                systemImage: SidebarDestination.ask.systemImage,
                message: L10n.agentDisabledDescription,
                actionTitle: L10n.settings
            ) {
                openSettings()
            }
        }
    }

    @ViewBuilder
    private func meetingDetailOrList(@ViewBuilder listContent: () -> some View) -> some View {
        if sidebarViewModel.selectedMeetingId != nil {
            meetingDetailView
        } else {
            listContent()
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

    /// 選択中のプロジェクト（なければ "Meetings" プロジェクト）に新規ミーティングを作成し、録音を開始する。
    private func startNewMeeting() {
        guard !viewModel.isListening,
              viewModel.analyzerReady,
              let dbQueue = sidebarViewModel.dbQueue,
              let vault = sidebarViewModel.currentVault else { return }

        // 選択中プロジェクト or 既定の "Meetings" プロジェクトを確定
        let projectId: UUID
        let projectName: String
        let projectURL: URL
        if let selected = sidebarViewModel.selectedProject,
           let selectedURL = sidebarViewModel.selectedProjectURL {
            projectId = selected.id
            projectName = selected.name
            projectURL = selectedURL
        } else if let fallback = sidebarViewModel.fetchOrCreateProject(name: "Meetings") {
            projectId = fallback.record.id
            projectName = fallback.record.name
            projectURL = fallback.url
            sidebarViewModel.selectProject(id: projectId, name: projectName)
            sidebarViewModel.selectedDestination = .projects
        } else {
            return
        }

        // 履歴表示中なら追記ではなく新規として扱うためクリア
        viewModel.clearCurrentMeeting()

        Task {
            await viewModel.startListening(
                dbQueue: dbQueue,
                projectURL: projectURL,
                projectId: projectId,
                projectName: projectName,
                vaultURL: vault.url
            )
            if let newMeetingId = viewModel.currentMeetingId {
                sidebarViewModel.selectMeeting(newMeetingId)
            }
        }
    }

    private func placeholderView(
        title: String,
        systemImage: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}
