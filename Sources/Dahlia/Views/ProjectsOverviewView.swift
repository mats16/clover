import AppKit
import SwiftUI

/// サイドバーの Projects から開く全プロジェクト一覧。
struct ProjectsOverviewView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case missingOnDisk

        var id: Self { self }

        var title: String {
            switch self {
            case .all:
                L10n.all
            case .missingOnDisk:
                L10n.missingOnDisk
            }
        }
    }

    var sidebarViewModel: SidebarViewModel

    @State private var filter: Filter = .all
    @State private var showNewProjectField = false
    @State private var newProjectName = ""
    @State private var editingProjectId: UUID?
    @State private var editingName = ""
    @FocusState private var isRenameFocused: Bool

    private var projects: [ProjectOverviewItem] {
        let allProjects = sidebarViewModel.allProjectItems

        switch filter {
        case .all:
            return allProjects
        case .missingOnDisk:
            return allProjects.filter(\.missingOnDisk)
        }
    }

    private var isMultiSelectMode: Bool {
        !sidebarViewModel.selectedProjectIds.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.projects)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.primary)

                    Menu {
                        ForEach(Filter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                if option == filter {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Label(L10n.filter, systemImage: "line.3.horizontal.decrease")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                if showNewProjectField {
                    newProjectInputField
                }

                if projects.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.noProjectsYet, systemImage: "folder")
                    } description: {
                        Text(filter == .all ? L10n.newProject : L10n.noProjectsMatchFilter)
                    } actions: {
                        if filter == .all {
                            Button(L10n.newProject, action: { showNewProjectField = true })
                        } else {
                            Button(L10n.all, action: resetFilter)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(projects) { item in
                            if editingProjectId == item.projectId {
                                projectRenameField(item)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            } else {
                                ProjectsOverviewRow(
                                    item: item,
                                    isSelected: sidebarViewModel.effectiveSelectedProjectIds.contains(item.projectId),
                                    isMultiSelectMode: isMultiSelectMode,
                                    isChecked: sidebarViewModel.selectedProjectIds.contains(item.projectId),
                                    onSelect: { handleRowActivation(item) },
                                    onToggleCheck: { toggleCheck(item) },
                                    onRename: { beginRename(item) },
                                    onOpenInFinder: {
                                        NSWorkspace.shared.open(sidebarViewModel.projectURL(for: item.projectName))
                                    },
                                    onDelete: {
                                        sidebarViewModel.deleteProject(id: item.projectId, name: item.projectName)
                                    },
                                    onRecreateFolder: {
                                        sidebarViewModel.recreateFolder(name: item.projectName)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, isMultiSelectMode ? 80 : 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .onDeleteCommand(perform: deleteSelection)
    }

    // MARK: - New Project Input

    private var newProjectInputField: some View {
        HStack {
            TextField(L10n.projectName, text: $newProjectName)
                .textFieldStyle(.plain)
                .onSubmit { createNewProject() }
            Button(L10n.create, action: createNewProject)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(L10n.close, systemImage: "xmark.circle.fill", action: cancelNewProjectCreation)
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Rename

    private func projectRenameField(_ item: ProjectOverviewItem) -> some View {
        TextField(L10n.projectName, text: $editingName)
            .textFieldStyle(.roundedBorder)
            .focused($isRenameFocused)
            .onSubmit { commitRename(item: item) }
            .onExitCommand { editingProjectId = nil }
            .onChange(of: isRenameFocused) { _, focused in
                if !focused { commitRename(item: item) }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                isRenameFocused = true
            }
    }

    // MARK: - Actions

    private func resetFilter() {
        filter = .all
    }

    private func handleRowActivation(_ item: ProjectOverviewItem) {
        let flags = NSEvent.modifierFlags

        if isMultiSelectMode, !flags.contains(.command), !flags.contains(.shift) {
            sidebarViewModel.toggleProjectSelection(item.projectId)
        } else if flags.contains(.command) {
            sidebarViewModel.toggleProjectSelection(item.projectId)
        } else if flags.contains(.shift) {
            sidebarViewModel.rangeSelectProject(item.projectId)
        } else {
            sidebarViewModel.singleSelectProjectFromOverview(item.projectId, name: item.projectName)
        }
    }

    private func toggleCheck(_ item: ProjectOverviewItem) {
        sidebarViewModel.toggleProjectSelection(item.projectId)
    }

    private func beginRename(_ item: ProjectOverviewItem) {
        editingName = item.projectName
        editingProjectId = item.projectId
    }

    private func commitRename(item: ProjectOverviewItem) {
        guard editingProjectId == item.projectId else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != item.projectName {
            sidebarViewModel.renameProject(id: item.projectId, name: item.projectName, newName: trimmed)
        }
        editingProjectId = nil
    }

    private func createNewProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        sidebarViewModel.createProject(name: name)
        newProjectName = ""
        showNewProjectField = false
    }

    private func cancelNewProjectCreation() {
        showNewProjectField = false
        newProjectName = ""
    }

    private func deleteSelection() {
        let ids = sidebarViewModel.effectiveSelectedProjectIds
        guard !ids.isEmpty else { return }

        if ids.count == 1, let id = ids.first,
           let item = sidebarViewModel.allProjectItems.first(where: { $0.projectId == id }) {
            sidebarViewModel.deleteProject(id: id, name: item.projectName)
        } else {
            sidebarViewModel.deleteProjects(ids: ids)
        }
    }
}

// MARK: - Project Row

private struct ProjectsOverviewRow: View {
    let item: ProjectOverviewItem
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    let onRename: () -> Void
    let onOpenInFinder: () -> Void
    let onDelete: () -> Void
    let onRecreateFolder: () -> Void

    @State private var isHovering = false

    private var showControls: Bool {
        isMultiSelectMode || isHovering
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                avatar
                    .opacity(showControls ? 0 : 1)

                Button(action: onToggleCheck) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(showControls ? 1 : 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.projectName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(displaySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.trailing, 36)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .trailing) {
            Menu {
                menuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 12)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .background(backgroundStyle)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isMultiSelectMode)
        .contextMenu {
            menuContent
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if item.missingOnDisk {
            Button(L10n.recreateFolder) { onRecreateFolder() }
            Divider()
        }
        Button(L10n.rename) { onRename() }
        if !item.missingOnDisk {
            Button(L10n.openInFinder) { onOpenInFinder() }
        }
        Divider()
        Button(L10n.delete, role: .destructive) { onDelete() }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(avatarGradient)
                .frame(width: 32, height: 32)

            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .bottomTrailing) {
            if item.missingOnDisk {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .background(
                        Circle()
                            .fill(.background)
                            .frame(width: 14, height: 14)
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private var backgroundStyle: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(isHovering ? 0.04 : 0.0))
    }

    private var displaySubtitle: String {
        if item.meetingCount == 0 {
            return L10n.noMeetings
        }
        return L10n.meetingCount(item.meetingCount)
    }

    private var avatarGradient: LinearGradient {
        let colors: [(Color, Color)] = [
            (.blue, .cyan),
            (.orange, .yellow),
            (.teal, .mint),
            (.indigo, .purple),
            (.pink, .red),
            (.green, .teal),
        ]
        let pair = colors[abs(item.projectId.hashValue) % colors.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilityLabel: String {
        "\(item.projectName), \(displaySubtitle)"
    }
}
