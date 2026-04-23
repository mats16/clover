import SwiftUI

/// 固定幅サイドバーと詳細ビューを構成するルートビュー。
struct ContentView: View {
    private let primarySidebarWidth: CGFloat = 220
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    let liveSubtitleOverlayService: LiveSubtitleOverlayService
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @State private var isPrimarySidebarPresented = true
    @State private var isAgentSidebarPresented = false
    @State private var pendingMeetingSelectionAfterNavigation: UUID?
    @State private var pendingNavigationRestoration: ContentNavigationState?
    @State private var navigationBackStack: [ContentNavigationState] = []
    @State private var navigationForwardStack: [ContentNavigationState] = []
    @State private var lastCommittedNavigationState: ContentNavigationState?
    @State private var isRestoringNavigationState = false

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
        }
        .background(WindowTitlebarConfigurator())
        .background {
            LiveSubtitleOverlaySyncView(
                store: viewModel.activeTranscriptStoreForAgent,
                isListening: viewModel.isListening,
                liveSubtitleOverlayService: liveSubtitleOverlayService
            )
        }
        .toolbar(content: windowToolbarContent)
        .onAppear(perform: initializeNavigationHistoryIfNeeded)
        .onDisappear {
            liveSubtitleOverlayService.hide()
        }
        .onChange(of: sidebarViewModel.selectedMeetingSelection) { oldSelection, newSelection in
            guard oldSelection != newSelection else { return }
            switch newSelection {
            case let .persisted(meetingId):
                handleMeetingSelection(meetingId)
            case let .draft(draftId):
                if viewModel.draftMeeting?.id != draftId {
                    viewModel.clearCurrentMeeting()
                }
            case nil:
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
                } else if sidebarViewModel.selectedMeetingSelection == nil {
                    sidebarViewModel.clearMeetingSelection()
                }
            }
            if oldValue != .projects, newValue == .projects {
                sidebarViewModel.clearProjectSelection()
                sidebarViewModel.deselectProject()
            }
            if newValue == .actionItems || newValue == .instructions,
               oldValue != newValue {
                sidebarViewModel.clearProjectSelection()
                sidebarViewModel.deselectProject()
            }
        }
        .onChange(of: viewModel.currentMeetingId) { oldId, newId in
            guard oldId != newId else { return }
            viewModel.resetAgentSegmentTrackingIfNeeded()
            if let newId,
               sidebarViewModel.selectedDestination == .meetings,
               sidebarViewModel.selectedMeetingSelection?.draftId != nil || sidebarViewModel.selectedMeetingSelection == nil {
                sidebarViewModel.selectMeeting(newId)
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

        if shouldShowNewChatButton {
            ToolbarItem(placement: .automatic) {
                newChatToolbarButton
            }
        }

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
            workspaceContent {
                HomeOverviewView(onSelectEvent: startDraftMeeting)
            }
        case .meetings:
            workspaceContent {
                meetingsOverviewContent
            }
        case .projects:
            workspaceContent {
                projectsWorkspaceContent
            }
        case .instructions:
            workspaceContent {
                InstructionsWorkspaceView(sidebarViewModel: sidebarViewModel)
            }
        case .actionItems:
            workspaceContent {
                actionItemsOverviewContent
            }
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

    private var newChatToolbarButton: some View {
        Button(action: viewModel.stopAgent) {
            Label(L10n.newChat, systemImage: "plus")
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
        }
        .help(L10n.newChat)
        .accessibilityLabel(L10n.newChat)
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
        sidebarViewModel.selectedDestination != .ask
    }

    private var shouldShowNewChatButton: Bool {
        viewModel.agentService != nil
    }

    private var currentNavigationState: ContentNavigationState {
        ContentNavigationState(
            destination: sidebarViewModel.selectedDestination,
            selectedProjectId: sidebarViewModel.selectedProject?.id,
            selectedProjectName: sidebarViewModel.selectedProject?.name,
            selectedMeetingId: sidebarViewModel.selectedMeetingId,
            selectedInstructionId: sidebarViewModel.selectedInstruction?.id
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
        case .home, .instructions, .actionItems, .ask:
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
            && sidebarViewModel.selectedMeetingSelection == nil
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

    private var shouldShowWorkspaceAgentSidebar: Bool {
        isAgentSidebarPresented && sidebarViewModel.selectedDestination != .ask
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
            sidebarViewModel.selectedMeetingSelection != nil
        case .home, .instructions, .actionItems, .ask:
            false
        }
    }

    private var meetingDetailView: some View {
        ControlPanelView(
            viewModel: viewModel,
            sidebarViewModel: sidebarViewModel
        )
    }

    @ViewBuilder
    private var projectsWorkspaceContent: some View {
        if sidebarViewModel.selectedMeetingSelection != nil {
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

    private var askWorkspaceContent: some View {
        AgentSidebarView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func meetingDetailOrList(@ViewBuilder listContent: () -> some View) -> some View {
        if sidebarViewModel.selectedMeetingSelection != nil {
            meetingDetailView
        } else {
            listContent()
        }
    }

    private func workspaceContent(@ViewBuilder content: () -> some View) -> some View {
        HSplitView {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    bottomOverlayBar
                }

            if shouldShowWorkspaceAgentSidebar {
                AgentSidebarView(viewModel: viewModel, sidebarViewModel: sidebarViewModel)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 480, maxHeight: .infinity)
                    .background(.background)
            }
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
        case .instructions:
            sidebarViewModel.clearProjectSelection()
            sidebarViewModel.deselectProject()
            sidebarViewModel.clearMeetingSelection()
            sidebarViewModel.selectInstruction(state.selectedInstructionId)
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

    private func startDraftMeeting(from event: GoogleCalendarEvent) {
        guard let dbQueue = sidebarViewModel.dbQueue,
              let vault = sidebarViewModel.currentVault else { return }

        let repository = MeetingRepository(dbQueue: dbQueue)
        if let existingMeetingId = try? repository.fetchMeetingIdForCalendarEvent(
            platform: CalendarEventRecord.googleCalendarPlatform,
            platformId: event.platformId
        ) {
            sidebarViewModel.deselectProject()
            sidebarViewModel.selectDestination(.meetings)
            sidebarViewModel.selectMeeting(existingMeetingId)
            return
        }

        sidebarViewModel.deselectProject()
        sidebarViewModel.clearMeetingSelection()
        viewModel.beginDraftMeeting(
            from: event,
            dbQueue: dbQueue,
            vaultURL: vault.url
        )
        if let draftId = viewModel.draftMeeting?.id {
            sidebarViewModel.selectDraftMeeting(draftId)
        }
        sidebarViewModel.selectDestination(.meetings)
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

private struct LiveSubtitleOverlaySyncView: View {
    @ObservedObject var store: TranscriptStore
    let isListening: Bool
    let liveSubtitleOverlayService: LiveSubtitleOverlayService

    @AppStorage("liveSubtitleOverlayEnabled") private var liveSubtitleOverlayEnabled = false
    @AppStorage("liveSubtitleOverlaySegmentCount") private var liveSubtitleOverlaySegmentCount = 2
    @AppStorage("liveSubtitleSourceMode") private var liveSubtitleSourceModeRawValue = LiveSubtitleSourceMode.includeMicrophone.rawValue
    @AppStorage("transcriptTranslationEnabled") private var transcriptTranslationEnabled = true
    @AppStorage("transcriptionLocale") private var transcriptionLocale = Locale.current.identifier
    @AppStorage("transcriptTranslationTargetLanguage") private var targetLanguageIdentifier = TranscriptTranslationLanguage.defaultIdentifier

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear(perform: syncOverlay)
            .onDisappear {
                liveSubtitleOverlayService.hide()
            }
            .onReceive(store.objectWillChange.debounce(for: .milliseconds(200), scheduler: RunLoop.main)) { _ in
                syncOverlay()
            }
            .onChange(of: isListening) { _, _ in
                syncOverlay()
            }
            .onChange(of: liveSubtitleOverlayEnabled) { _, _ in
                syncOverlay()
            }
            .onChange(of: liveSubtitleOverlaySegmentCount) { _, _ in
                syncOverlay()
            }
            .onChange(of: liveSubtitleSourceModeRawValue) { _, _ in
                syncOverlay()
            }
            .onChange(of: transcriptTranslationEnabled) { _, _ in
                syncOverlay()
            }
            .onChange(of: transcriptionLocale) { _, _ in
                syncOverlay()
            }
            .onChange(of: targetLanguageIdentifier) { _, _ in
                syncOverlay()
            }
    }

    private func syncOverlay() {
        guard isListening, liveSubtitleOverlayEnabled else {
            liveSubtitleOverlayService.hide()
            return
        }

        let payload = LiveSubtitleOverlayPayload.latest(
            from: store.segments,
            sourceMode: LiveSubtitleSourceMode(rawValue: liveSubtitleSourceModeRawValue) ?? .includeMicrophone,
            transcriptionLocaleIdentifier: transcriptionLocale,
            translationEnabled: transcriptTranslationEnabled,
            targetLanguageIdentifier: targetLanguageIdentifier,
            maxEntries: max(1, liveSubtitleOverlaySegmentCount)
        )

        liveSubtitleOverlayService.update(payload: payload)
    }
}
