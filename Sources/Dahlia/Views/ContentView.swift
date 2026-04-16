import SwiftUI

/// 固定幅サイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    private let primarySidebarWidth: CGFloat = 220
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var isPrimarySidebarPresented = true
    @State private var isAgentSidebarPresented = false
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 0) {
            if isPrimarySidebarPresented {
                SidebarView(
                    sidebarViewModel: sidebarViewModel,
                    onSelectVault: onSelectVault,
                    onStartNewMeeting: startNewMeeting,
                    isNewMeetingDisabled: isNewMeetingDisabled
                )
                .frame(width: primarySidebarWidth)

                Divider()
            }

            detailArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if shouldShowBottomOverlayBar {
                        HStack(spacing: 12) {
                            if shouldShowFloatingActionBar {
                                FloatingActionBar(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                            }

                            if shouldShowBatchProjectSelectionBar {
                                BatchSelectionBar(
                                    selectedCount: sidebarViewModel.selectedProjectIds.count,
                                    onClearSelection: {
                                        sidebarViewModel.clearProjectSelection()
                                    },
                                    onDelete: {
                                        sidebarViewModel.deleteProjects(ids: sidebarViewModel.selectedProjectIds)
                                    }
                                )
                            } else if shouldShowBatchMeetingSelectionBar {
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
        .background(WindowTitlebarConfigurator())
        .toolbar { windowToolbarContent }
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
            if oldValue != .projects, newValue == .projects {
                sidebarViewModel.clearProjectSelection()
                sidebarViewModel.deselectProject()
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

    @ToolbarContentBuilder
    private var windowToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            primarySidebarToggle
        }

        ToolbarSpacer(.flexible, placement: .automatic)

        if shouldShowAgentSidebarToggle {
            ToolbarItem(placement: .automatic) {
                agentSidebarToggle
            }
        }
    }

    // MARK: - Detail Area

    @ViewBuilder
    private var detailArea: some View {
        switch sidebarViewModel.selectedDestination {
        case .home:
            HomeOverviewView()
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
                .foregroundStyle(isAgentSidebarPresented ? Color.accentColor : Color.secondary)
        }
        .help(L10n.agent)
        .accessibilityLabel(L10n.agent)
    }

    private var primarySidebarToggle: some View {
        Button {
            withAnimation(.snappy) {
                isPrimarySidebarPresented.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .foregroundStyle(.secondary)
        }
        .help(isPrimarySidebarPresented ? L10n.hideSidebar : L10n.showSidebar)
        .accessibilityLabel(isPrimarySidebarPresented ? L10n.hideSidebar : L10n.showSidebar)
    }

    private var shouldShowAgentSidebarToggle: Bool {
        appSettings.agentEnabled && sidebarViewModel.selectedDestination != .ask
    }

    private var isNewMeetingDisabled: Bool {
        !viewModel.analyzerReady || sidebarViewModel.currentVault == nil || viewModel.isListening
    }

    private var shouldShowFloatingActionBar: Bool {
        viewModel.isListening || isShowingMeetingDetail
    }

    private var shouldShowBatchMeetingSelectionBar: Bool {
        sidebarViewModel.selectedDestination == .meetings
            && sidebarViewModel.selectedMeetingId == nil
            && !sidebarViewModel.selectedMeetingIds.isEmpty
    }

    private var shouldShowBatchProjectSelectionBar: Bool {
        sidebarViewModel.selectedDestination == .projects
            && sidebarViewModel.selectedProject == nil
            && !sidebarViewModel.selectedProjectIds.isEmpty
    }

    private var shouldShowBatchSelectionBar: Bool {
        shouldShowBatchMeetingSelectionBar || shouldShowBatchProjectSelectionBar
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

    @ViewBuilder
    private var projectsWorkspaceContent: some View {
        if sidebarViewModel.selectedMeetingId != nil {
            meetingDetailView
        } else if sidebarViewModel.selectedProject != nil {
            ProjectDetailView(
                sidebarViewModel: sidebarViewModel,
                onStartNewMeeting: startNewMeeting
            )
        } else {
            ProjectsOverviewView(sidebarViewModel: sidebarViewModel)
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
              let vault = sidebarViewModel.currentVault,
              let item = sidebarViewModel.allMeetings.first(where: { $0.meetingId == meetingId }) else { return }

        viewModel.loadMeeting(
            meetingId,
            dbQueue: dbQueue,
            projectURL: item.projectName.map { sidebarViewModel.projectURL(for: $0) },
            projectId: item.projectId,
            projectName: item.projectName,
            vaultURL: vault.url
        )
    }

    /// 選択中のプロジェクト、または未所属の新規ミーティングに録音を開始する。
    private func startNewMeeting() {
        guard !viewModel.isListening,
              viewModel.analyzerReady,
              let dbQueue = sidebarViewModel.dbQueue,
              let vault = sidebarViewModel.currentVault else { return }

        let ctx = sidebarViewModel.selectedProjectContext

        // 履歴表示中なら追記ではなく新規として扱うためクリア
        viewModel.clearCurrentMeeting()
        if ctx.projectId == nil {
            sidebarViewModel.deselectProjectKeepingMeetingSelection()
        }

        Task {
            await viewModel.startListening(
                dbQueue: dbQueue,
                projectURL: ctx.projectURL,
                vaultId: vault.id,
                projectId: ctx.projectId,
                projectName: ctx.projectName,
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
