import SwiftUI

/// 固定幅サイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    private let primarySidebarWidth: CGFloat = 220
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var isPrimarySidebarPresented = true
    @State private var isAgentSidebarPresented = false
    @State private var pendingMeetingSelectionAfterNavigation: UUID?
    @State private var pendingNavigationRestoration: ContentNavigationState?
    @State private var navigationBackStack: [ContentNavigationState] = []
    @State private var navigationForwardStack: [ContentNavigationState] = []
    @State private var lastCommittedNavigationState: ContentNavigationState?
    @State private var isRestoringNavigationState = false
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
                    bottomOverlayBar
                }
        }
        .background(WindowTitlebarConfigurator())
        .toolbar(content: windowToolbarContent)
        .onAppear(perform: initializeNavigationHistoryIfNeeded)
        .onChange(of: sidebarViewModel.selectedMeetingId) { oldId, newId in
            guard oldId != newId else { return }
            if let newId {
                handleMeetingSelection(newId)
            } else {
                viewModel.clearCurrentMeeting()
            }
        }
        .onChange(of: sidebarViewModel.selectedDestination) { oldValue, newValue in
            if applyPendingNavigationRestorationIfNeeded(for: newValue) {
                return
            }
            if oldValue != .meetings, newValue == .meetings {
                if let pendingMeetingSelectionAfterNavigation {
                    sidebarViewModel.selectMeeting(pendingMeetingSelectionAfterNavigation)
                    self.pendingMeetingSelectionAfterNavigation = nil
                } else {
                    sidebarViewModel.clearMeetingSelection()
                }
            }
            if oldValue != .projects, newValue == .projects {
                sidebarViewModel.clearProjectSelection()
                sidebarViewModel.deselectProject()
            }
            if oldValue != .actionItems, newValue == .actionItems {
                sidebarViewModel.clearProjectSelection()
                sidebarViewModel.deselectProject()
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
        .onChange(of: currentNavigationState, handleNavigationStateChange)
        .onChange(of: sidebarViewModel.currentVault?.id) { _, _ in
            resetNavigationHistory()
        }
    }

    @ToolbarContentBuilder
    private func windowToolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            primarySidebarToggle
            historyNavigationControls
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
            actionItemsOverviewContent
        case .ask:
            askWorkspaceContent
        }
    }

    private var agentSidebarToggle: some View {
        Button {
            isAgentSidebarPresented.toggle()
        } label: {
            Label(L10n.agent, systemImage: "sidebar.right")
                .foregroundStyle(isAgentSidebarPresented ? Color.accentColor : Color.secondary)
                .labelStyle(.iconOnly)
        }
        .help(L10n.agent)
        .accessibilityLabel(L10n.agent)
    }

    private var historyNavigationControls: some View {
        HStack(spacing: 6) {
            navigationBackButton
            navigationForwardButton
        }
    }

    private var navigationBackButton: some View {
        Button(action: navigateBackward) {
            Label(L10n.back, systemImage: "chevron.left")
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
        }
        .disabled(!canNavigateBackward)
        .help(L10n.back)
        .accessibilityLabel(L10n.back)
    }

    private var navigationForwardButton: some View {
        Button(action: navigateForward) {
            Label(L10n.forward, systemImage: "chevron.right")
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
        }
        .disabled(!canNavigateForward)
        .help(L10n.forward)
        .accessibilityLabel(L10n.forward)
    }

    private var primarySidebarToggle: some View {
        Button {
            withAnimation(.snappy) {
                isPrimarySidebarPresented.toggle()
            }
        } label: {
            Label(
                isPrimarySidebarPresented ? L10n.hideSidebar : L10n.showSidebar,
                systemImage: "sidebar.left"
            )
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
        }
        .help(isPrimarySidebarPresented ? L10n.hideSidebar : L10n.showSidebar)
        .accessibilityLabel(isPrimarySidebarPresented ? L10n.hideSidebar : L10n.showSidebar)
    }

    private var shouldShowAgentSidebarToggle: Bool {
        appSettings.agentEnabled && sidebarViewModel.selectedDestination != .ask
    }

    private var currentNavigationState: ContentNavigationState {
        ContentNavigationState(
            destination: sidebarViewModel.selectedDestination,
            selectedProjectId: sidebarViewModel.selectedProject?.id,
            selectedProjectName: sidebarViewModel.selectedProject?.name,
            selectedMeetingId: sidebarViewModel.selectedMeetingId
        )
    }

    private var canNavigateBackward: Bool {
        !navigationBackStack.isEmpty
    }

    private var canNavigateForward: Bool {
        !navigationForwardStack.isEmpty
    }

    private var isNewMeetingDisabled: Bool {
        !viewModel.analyzerReady || sidebarViewModel.currentVault == nil || viewModel.isListening
    }

    private var shouldShowFloatingActionBar: Bool {
        viewModel.isListening || isShowingMeetingDetail
    }

    private var activeRecordingMeetingId: UUID? {
        guard viewModel.isListening else { return nil }
        return viewModel.activeMeetingIdForSessionControls
    }

    private var activeRecordingMeetingItem: MeetingOverviewItem? {
        guard let activeRecordingMeetingId else { return nil }
        return sidebarViewModel.allMeetings.first(where: { $0.meetingId == activeRecordingMeetingId })
    }

    private var shouldShowRecordingMeetingShortcut: Bool {
        guard let activeRecordingMeetingId else { return false }

        return switch sidebarViewModel.selectedDestination {
        case .meetings, .projects:
            sidebarViewModel.selectedMeetingId != activeRecordingMeetingId
        case .home, .actionItems, .ask:
            true
        }
    }

    private var floatingActionBarRecordingMeetingTitle: String? {
        guard shouldShowRecordingMeetingShortcut else { return nil }
        let name = activeRecordingMeetingItem?.meetingName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? L10n.newMeeting : name
    }

    private var floatingActionBarOpenMeetingAction: (() -> Void)? {
        guard shouldShowRecordingMeetingShortcut else { return nil }
        return {
            navigateToRecordingMeeting()
        }
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

    @ViewBuilder
    private var bottomOverlayBar: some View {
        if shouldShowBottomOverlayBar {
            HStack(spacing: 12) {
                if shouldShowFloatingActionBar {
                    FloatingActionBar(
                        viewModel: viewModel,
                        sidebarViewModel: sidebarViewModel,
                        recordingMeetingTitle: floatingActionBarRecordingMeetingTitle,
                        onOpenRecordingMeeting: floatingActionBarOpenMeetingAction
                    )
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
            ProjectDetailView(sidebarViewModel: sidebarViewModel)
        } else {
            ProjectsOverviewView(sidebarViewModel: sidebarViewModel)
        }
    }

    private var meetingsOverviewContent: some View {
        meetingDetailOrList {
            MeetingsOverviewView(
                sidebarViewModel: sidebarViewModel,
                onSelectMeeting: { _ in }
            )
        }
    }

    private var actionItemsOverviewContent: some View {
        ActionItemsOverviewView(sidebarViewModel: sidebarViewModel)
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

    private func initializeNavigationHistoryIfNeeded() {
        guard lastCommittedNavigationState == nil else { return }
        lastCommittedNavigationState = currentNavigationState
    }

    private func resetNavigationHistory() {
        pendingNavigationRestoration = nil
        navigationBackStack.removeAll()
        navigationForwardStack.removeAll()
        lastCommittedNavigationState = nil
        isRestoringNavigationState = false
    }

    private func handleNavigationStateChange(_ oldValue: ContentNavigationState, _ newValue: ContentNavigationState) {
        guard oldValue != newValue else { return }
        guard !isRestoringNavigationState else { return }
        initializeNavigationHistoryIfNeeded()
        guard let lastCommittedNavigationState, lastCommittedNavigationState != newValue else { return }

        navigationBackStack.append(lastCommittedNavigationState)
        navigationForwardStack.removeAll()
        self.lastCommittedNavigationState = newValue
    }

    private func navigateBackward() {
        guard let previousState = navigationBackStack.popLast() else { return }
        navigationForwardStack.append(currentNavigationState)
        restoreNavigationState(previousState)
    }

    private func navigateForward() {
        guard let nextState = navigationForwardStack.popLast() else { return }
        navigationBackStack.append(currentNavigationState)
        restoreNavigationState(nextState)
    }

    private func restoreNavigationState(_ state: ContentNavigationState) {
        guard state != currentNavigationState else {
            lastCommittedNavigationState = state
            return
        }

        isRestoringNavigationState = true
        pendingNavigationRestoration = state

        if sidebarViewModel.selectedDestination == state.destination {
            _ = applyPendingNavigationRestorationIfNeeded(for: state.destination)
        } else {
            sidebarViewModel.selectDestination(state.destination)
        }
    }

    private func applyPendingNavigationRestorationIfNeeded(for destination: SidebarDestination) -> Bool {
        guard let state = pendingNavigationRestoration, state.destination == destination else { return false }
        applyNavigationSelection(for: state)
        pendingNavigationRestoration = nil
        finalizeNavigationRestoration()
        return true
    }

    private func finalizeNavigationRestoration() {
        DispatchQueue.main.async {
            lastCommittedNavigationState = currentNavigationState
            isRestoringNavigationState = false
        }
    }

    private func applyNavigationSelection(for state: ContentNavigationState) {
        switch state.destination {
        case .projects:
            sidebarViewModel.clearProjectSelection()

            if let project = resolvedProjectSelection(for: state) {
                sidebarViewModel.selectProject(id: project.id, name: project.name)
            } else {
                sidebarViewModel.deselectProject()
            }

            if let meetingId = restoredMeetingId(for: state) {
                sidebarViewModel.selectMeeting(meetingId)
            } else {
                sidebarViewModel.clearMeetingSelection()
            }
        case .meetings:
            sidebarViewModel.clearProjectSelection()
            sidebarViewModel.deselectProject()

            if let meetingId = restoredMeetingId(for: state) {
                sidebarViewModel.selectMeeting(meetingId)
            } else {
                sidebarViewModel.clearMeetingSelection()
            }
        case .home, .actionItems, .ask:
            sidebarViewModel.clearProjectSelection()
            sidebarViewModel.deselectProject()
        }
    }

    private func resolvedProjectSelection(for state: ContentNavigationState) -> (id: UUID, name: String)? {
        if let selectedProjectId = state.selectedProjectId,
           let item = sidebarViewModel.allProjectItems.first(where: { $0.projectId == selectedProjectId }) {
            return (item.projectId, item.projectName)
        }

        if let meetingId = restoredMeetingId(for: state),
           let item = sidebarViewModel.allMeetings.first(where: { $0.meetingId == meetingId }),
           let projectId = item.projectId,
           let projectName = item.projectName {
            return (projectId, projectName)
        }

        if let selectedProjectId = state.selectedProjectId,
           let selectedProjectName = state.selectedProjectName {
            return (selectedProjectId, selectedProjectName)
        }

        return nil
    }

    private func restoredMeetingId(for state: ContentNavigationState) -> UUID? {
        guard let selectedMeetingId = state.selectedMeetingId else { return nil }
        guard sidebarViewModel.allMeetings.contains(where: { $0.meetingId == selectedMeetingId }) else { return nil }
        return selectedMeetingId
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

    private func navigateToRecordingMeeting() {
        guard let activeRecordingMeetingId else { return }

        if sidebarViewModel.selectedDestination == .meetings {
            if sidebarViewModel.selectedMeetingId == activeRecordingMeetingId {
                viewModel.returnToRecordingMeeting()
            } else {
                sidebarViewModel.selectMeeting(activeRecordingMeetingId)
            }
            return
        }

        pendingMeetingSelectionAfterNavigation = activeRecordingMeetingId
        sidebarViewModel.selectDestination(.meetings)
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
