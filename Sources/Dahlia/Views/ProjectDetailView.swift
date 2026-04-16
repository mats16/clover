import AppKit
import SwiftUI

private extension String {
    var projectDisplayName: String {
        split(separator: "/").last.map(String.init) ?? self
    }
}

private enum ProjectContextEditorLayout {
    static let editorPadding = EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
}

private enum ProjectDetailTab: String, CaseIterable, Identifiable {
    case meetings
    case context
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meetings: L10n.meetings
        case .context: L10n.context
        case .settings: L10n.settings
        }
    }
}

private struct ProjectDetailTabBar: View {
    @Binding var selection: ProjectDetailTab
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(ProjectDetailTab.allCases) { tab in
                    ProjectDetailTabButton(
                        tab: tab,
                        isSelected: selection == tab,
                        namespace: tabNamespace
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selection = tab
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
        }
    }
}

private struct ProjectDetailTabButton: View {
    let tab: ProjectDetailTab
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? .primary : .tertiary)

                Spacer()
                    .frame(height: 3)
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 3)
                        .padding(.horizontal, 6)
                        .matchedGeometryEffect(id: "projectActiveTab", in: namespace)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}

private struct ProjectNameHeader: View {
    let project: ProjectRecord
    @Binding var isEditing: Bool
    @Binding var editingName: String
    @FocusState.Binding var isFocused: Bool
    let onBeginEditing: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onEditorTap: () -> Void

    private var displayName: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return L10n.projectName
        }
        return trimmed
    }

    private var projectIcon: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    var body: some View {
        HStack(spacing: 10) {
            projectIcon

            Group {
                if isEditing {
                    TextField(L10n.projectName, text: $editingName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 28, weight: .semibold))
                        .focused($isFocused)
                        .onSubmit(onCommit)
                        .onExitCommand(perform: onCancel)
                        .onChange(of: isFocused) { _, focused in
                            if !focused, isEditing {
                                onCommit()
                            }
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                onEditorTap()
                            }
                        )
                        .task {
                            editingName = project.name.projectDisplayName
                            try? await Task.sleep(for: .milliseconds(50))
                            isFocused = true
                        }
                } else {
                    Button(action: onBeginEditing) {
                        HStack(spacing: 6) {
                            Text(displayName)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.rename)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: project.id) { _, _ in
            isEditing = false
            editingName = project.name.projectDisplayName
        }
        .onChange(of: project.name) { _, newName in
            if !isEditing {
                editingName = newName.projectDisplayName
            }
        }
    }
}

private struct ProjectDetailMeetingRow: View {
    let meeting: MeetingRecord
    let tags: [TagInfo]
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void

    @State private var isHovering = false

    private var showSelectionControl: Bool {
        isMultiSelectMode || isHovering
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Button(action: onSelect) {
                MeetingListRow(
                    meeting: meeting,
                    tags: tags,
                    style: .compact,
                    showAvatar: !showSelectionControl,
                    showsSubtitle: false
                )
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.primary.opacity(0.06) : .clear)
                )
            }
            .buttonStyle(.plain)

            Button(action: onToggleCheck) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .opacity(showSelectionControl ? 1 : 0)
            .allowsHitTesting(showSelectionControl)
        }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: showSelectionControl)
    }
}

struct ProjectDetailView: View {
    var sidebarViewModel: SidebarViewModel

    @State private var selectedTab: ProjectDetailTab = .meetings
    @State private var isEditingProjectName = false
    @State private var editingProjectName = ""
    @State private var didTapInsideProjectNameEditor = false
    @State private var contextText = ""
    @State private var lastSavedContextText = ""
    @State private var contextFileURL: URL?
    @State private var contextErrorMessage: String?
    @State private var hasLoadedContext = false
    @State private var contextSaveTask: Task<Void, Never>?
    @State private var didTapInsideContextEditor = false
    @FocusState private var isProjectNameFieldFocused: Bool
    @FocusState private var isContextEditorFocused: Bool

    private let folderService = FolderProjectService()

    var body: some View {
        VStack(spacing: 12) {
            if let project = currentProject {
                ProjectNameHeader(
                    project: project,
                    isEditing: $isEditingProjectName,
                    editingName: $editingProjectName,
                    isFocused: $isProjectNameFieldFocused,
                    onBeginEditing: beginProjectRename,
                    onCommit: commitProjectRename,
                    onCancel: cancelProjectRename,
                    onEditorTap: markProjectNameEditorTap
                )
                .padding(.top, -12)
            }

            ProjectDetailTabBar(selection: $selectedTab)

            Group {
                switch selectedTab {
                case .meetings:
                    meetingsTabContent
                case .context:
                    contextTabContent
                case .settings:
                    settingsTabContent
                }
            }
            .frame(minHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tabContentBackgroundColor)
            )

            if let contextErrorMessage, selectedTab == .context {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(contextErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissFocusedInputs()
            }
        )
        .task(id: currentProject?.id) {
            selectedTab = .meetings
            cancelProjectRename()
            await MainActor.run {
                resetContextState()
            }
            loadContextForCurrentProject()
        }
        .onChange(of: contextText) { _, newValue in
            scheduleContextSave(for: newValue)
        }
        .onDisappear {
            persistContextIfNeeded()
            contextSaveTask?.cancel()
        }
        .onDeleteCommand {
            guard selectedTab == .meetings else { return }
            let ids = sidebarViewModel.effectiveSelectedIds
            guard !ids.isEmpty else { return }
            if ids.count == 1, let single = ids.first {
                sidebarViewModel.deleteMeeting(id: single)
            } else {
                sidebarViewModel.deleteMeetings(ids: ids)
            }
        }
        .navigationTitle(headerTitle)
    }

    @ViewBuilder
    private var meetingsTabContent: some View {
        if meetings.isEmpty {
            ContentUnavailableView {
                Label(L10n.noMeetingsYet, systemImage: "waveform")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(meetings, id: \.id) { meeting in
                        ProjectDetailMeetingRow(
                            meeting: meeting,
                            tags: meetingItemsById[meeting.id]?.tags ?? [],
                            isSelected: isMeetingActive(meeting.id),
                            isMultiSelectMode: isMultiSelectMode,
                            isChecked: sidebarViewModel.selectedMeetingIds.contains(meeting.id),
                            onSelect: { handleMeetingRowActivation(meeting) },
                            onToggleCheck: { toggleMeetingSelection(meeting) }
                        )

                        if meeting.id != meetings.last?.id {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .padding(.bottom, shouldShowMeetingBatchSelectionBar ? 80 : 0)
            }
            .overlay(alignment: .bottom) {
                if shouldShowMeetingBatchSelectionBar {
                    BatchSelectionBar(
                        selectedCount: sidebarViewModel.selectedMeetingIds.count,
                        onClearSelection: {
                            sidebarViewModel.clearMeetingSelection()
                        },
                        onDelete: {
                            sidebarViewModel.deleteMeetings(ids: sidebarViewModel.selectedMeetingIds)
                        }
                    )
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var contextTabContent: some View {
        if isCurrentProjectMissingOnDisk {
            ContentUnavailableView {
                Label(L10n.context, systemImage: "doc.text")
            } description: {
                Text(L10n.folderMissing)
            } actions: {
                if let currentProject {
                    Button(L10n.recreateFolder) {
                        sidebarViewModel.recreateFolder(name: currentProject.name)
                        loadContextForCurrentProject()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $contextText)
                    .font(.body)
                    .focused($isContextEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(ProjectContextEditorLayout.editorPadding)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            didTapInsideContextEditor = true
                        }
                    )
                    .disabled(!hasLoadedContext)

                if !hasLoadedContext {
                    ProgressView()
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .padding(12)
        }
    }

    private var settingsTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProjectSettingRow(title: L10n.projectName) {
                    Text(currentProject?.name ?? "")
                        .font(.subheadline)
                        .textSelection(.enabled)
                }

                ProjectSettingRow(title: L10n.location) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(currentProjectURL?.path ?? "")
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(L10n.openInFinder) {
                            guard let currentProjectURL else { return }
                            NSWorkspace.shared.open(currentProjectURL)
                        }
                        .buttonStyle(.link)
                        .disabled(isCurrentProjectMissingOnDisk || currentProjectURL == nil)
                    }
                }
            }
            .padding(16)
        }
    }

    private var currentProject: ProjectRecord? {
        sidebarViewModel.selectedProject
    }

    private var currentProjectItem: ProjectOverviewItem? {
        guard let currentProject else { return nil }
        return sidebarViewModel.allProjectItems.first(where: { $0.projectId == currentProject.id })
    }

    private var currentProjectURL: URL? {
        sidebarViewModel.selectedProjectURL
    }

    private var meetings: [MeetingRecord] {
        sidebarViewModel.meetingsForSelectedProject
    }

    private var meetingItemsById: [UUID: MeetingOverviewItem] {
        let projectMeetingIds = Set(meetings.map(\.id))
        return Dictionary(
            uniqueKeysWithValues: sidebarViewModel.allMeetings
                .filter { projectMeetingIds.contains($0.meetingId) }
                .map { ($0.meetingId, $0) }
        )
    }

    private var isCurrentProjectMissingOnDisk: Bool {
        currentProjectItem?.missingOnDisk ?? false
    }

    private var tabContentBackgroundColor: Color {
        switch selectedTab {
        case .context:
            Color(nsColor: .textBackgroundColor)
        case .settings:
            .clear
        case .meetings:
            Color(nsColor: .controlBackgroundColor)
        }
    }

    private var isMultiSelectMode: Bool {
        !sidebarViewModel.selectedMeetingIds.isEmpty
    }

    private var shouldShowMeetingBatchSelectionBar: Bool {
        selectedTab == .meetings
            && sidebarViewModel.selectedMeetingId == nil
            && !sidebarViewModel.selectedMeetingIds.isEmpty
    }

    private var headerTitle: String {
        currentProject?.name.projectDisplayName ?? L10n.projects
    }

    private func isMeetingActive(_ id: UUID) -> Bool {
        sidebarViewModel.effectiveSelectedIds.contains(id)
    }

    private func handleMeetingRowActivation(_ meeting: MeetingRecord) {
        guard let currentProject else { return }
        let flags = NSEvent.modifierFlags

        if flags.contains(.command) || (isMultiSelectMode && !flags.contains(.shift)) {
            sidebarViewModel.toggleMeetingSelection(
                meeting.id,
                projectId: currentProject.id,
                projectName: currentProject.name
            )
        } else if flags.contains(.shift) {
            sidebarViewModel.rangeSelectMeeting(
                meeting.id,
                projectId: currentProject.id,
                projectName: currentProject.name
            )
        } else {
            sidebarViewModel.singleSelectMeeting(
                meeting.id,
                projectId: currentProject.id,
                projectName: currentProject.name
            )
        }
    }

    private func toggleMeetingSelection(_ meeting: MeetingRecord) {
        guard let currentProject else { return }
        sidebarViewModel.toggleMeetingSelection(
            meeting.id,
            projectId: currentProject.id,
            projectName: currentProject.name
        )
    }

    private func beginProjectRename() {
        editingProjectName = currentProject?.name.projectDisplayName ?? ""
        isEditingProjectName = true
        didTapInsideProjectNameEditor = false
    }

    private func cancelProjectRename() {
        editingProjectName = currentProject?.name.projectDisplayName ?? ""
        isEditingProjectName = false
        isProjectNameFieldFocused = false
        didTapInsideProjectNameEditor = false
    }

    private func commitProjectRename() {
        guard isEditingProjectName, let currentProject else { return }

        let trimmed = editingProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelProjectRename()
            return
        }

        let parentPath = currentProject.name.split(separator: "/").dropLast().joined(separator: "/")
        let newName = parentPath.isEmpty ? trimmed : "\(parentPath)/\(trimmed)"
        sidebarViewModel.renameProject(id: currentProject.id, name: currentProject.name, newName: newName)
        isEditingProjectName = false
        isProjectNameFieldFocused = false
        didTapInsideProjectNameEditor = false
    }

    private func markProjectNameEditorTap() {
        didTapInsideProjectNameEditor = true
    }

    private func dismissFocusedInputs() {
        if didTapInsideProjectNameEditor {
            didTapInsideProjectNameEditor = false
        } else if isEditingProjectName {
            isProjectNameFieldFocused = false
        }

        if didTapInsideContextEditor {
            didTapInsideContextEditor = false
        } else if isContextEditorFocused {
            isContextEditorFocused = false
        }
    }

    private func resetContextState() {
        contextSaveTask?.cancel()
        contextText = ""
        lastSavedContextText = ""
        contextFileURL = nil
        contextErrorMessage = nil
        hasLoadedContext = false
    }

    private func loadContextForCurrentProject() {
        guard let currentProjectURL else { return }
        guard FileManager.default.fileExists(atPath: currentProjectURL.path) else { return }
        guard let fileURL = folderService.ensureContextFileExists(at: currentProjectURL) else {
            contextErrorMessage = L10n.contextCreationFailed
            return
        }

        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            contextFileURL = fileURL
            contextText = text
            lastSavedContextText = text
            contextErrorMessage = nil
            hasLoadedContext = true
        } catch {
            contextErrorMessage = error.localizedDescription
        }
    }

    private func scheduleContextSave(for text: String) {
        guard hasLoadedContext,
              let contextFileURL,
              text != lastSavedContextText else { return }

        contextSaveTask?.cancel()
        contextSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                try text.write(to: contextFileURL, atomically: true, encoding: .utf8)
                await MainActor.run {
                    lastSavedContextText = text
                    contextErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    contextErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func persistContextIfNeeded() {
        guard hasLoadedContext,
              let contextFileURL,
              contextText != lastSavedContextText else { return }

        do {
            try contextText.write(to: contextFileURL, atomically: true, encoding: .utf8)
            lastSavedContextText = contextText
            contextErrorMessage = nil
        } catch {
            contextErrorMessage = error.localizedDescription
        }
    }
}

private struct ProjectSettingRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
