import SwiftUI

/// プロジェクト一覧を表示するサイドバー。
struct SidebarView: View {
    @ObservedObject var viewModel: CaptionViewModel
    @Bindable var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var editingProjectId: UUID?
    @State private var editingName = ""
    @State private var showNewProjectField = false
    @State private var newProjectName = ""
    @State private var presentedErrorMessage = ""
    @State private var isPresentingError = false
    @FocusState private var isRenameFocused: Bool

    /// 信号ボタン（赤黄緑）を避けるための上部パディング
    private let trafficLightPadding: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            // 信号ボタン領域 + 新規プロジェクトボタン
            HStack {
                Spacer()
                Button(action: { showNewProjectField = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L10n.newProject)
            }
            .padding(.top, trafficLightPadding)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            if showNewProjectField {
                newProjectInputField
            }

            sidebarContent

            Spacer(minLength: 0)

            Divider()
            sidebarFooter
        }
        .onChange(of: sidebarViewModel.lastError) { _, newError in
            presentedErrorMessage = newError ?? ""
            isPresentingError = newError != nil
        }
        .onChange(of: isPresentingError) { _, isPresented in
            if !isPresented {
                sidebarViewModel.lastError = nil
            }
        }
        .alert("エラー", isPresented: $isPresentingError) {} message: {
            Text(presentedErrorMessage)
        }
    }

    private var sidebarContent: some View {
        let selectedProjectId = sidebarViewModel.selectedProject?.id

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sidebarViewModel.visibleFlatProjects) { row in
                    let isSelected = selectedProjectId == row.id
                    ProjectSectionView(
                        row: row,
                        isSelected: isSelected,
                        sidebarViewModel: sidebarViewModel,
                        editingProjectId: $editingProjectId,
                        editingName: $editingName,
                        isRenameFocused: $isRenameFocused
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - New Project Input

    private var newProjectInputField: some View {
        VStack(spacing: 0) {
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
            Divider()
        }
    }

    // MARK: - Sidebar Footer

    private var sidebarFooter: some View {
        HStack(spacing: 0) {
            VaultMenuButton(
                currentVault: sidebarViewModel.currentVault,
                allVaults: sidebarViewModel.allVaults,
                onSelectVault: onSelectVault,
                onManageVaults: { openWindow(id: WindowID.vaultManager) }
            )

            Spacer()

            Button(L10n.settings, systemImage: "gearshape") {
                openSettings()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
            .help(L10n.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

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
}

// MARK: - Project Section (独立 observation scope)

/// プロジェクト1行分の Section。
private struct ProjectSectionView: View {
    let row: FlatProjectRow
    let isSelected: Bool
    let sidebarViewModel: SidebarViewModel
    @Binding var editingProjectId: UUID?
    @Binding var editingName: String
    var isRenameFocused: FocusState<Bool>.Binding

    private static let indentUnit: CGFloat = 12

    var body: some View {
        projectHeader(row, isSelected: isSelected)
            .padding(.leading, CGFloat(row.depth) * Self.indentUnit)
    }

    // MARK: - Project Header

    @ViewBuilder
    private func projectHeader(_ row: FlatProjectRow, isSelected: Bool) -> some View {
        if editingProjectId == row.id {
            projectRenameField(row)
        } else {
            ProjectHeaderRow(
                row: row,
                isSelected: isSelected,
                onSelect: { selectRow(row) },
                onRename: {
                    editingName = row.displayName
                    editingProjectId = row.id
                },
                onEditContext: {
                    sidebarViewModel.openContext(projectName: row.name)
                },
                onOpenInFinder: {
                    NSWorkspace.shared.open(sidebarViewModel.projectURL(for: row.name))
                },
                onDelete: {
                    sidebarViewModel.deleteProject(id: row.id, name: row.name)
                },
                onRecreateFolder: {
                    sidebarViewModel.recreateFolder(name: row.name)
                },
                onDropMeetings: { meetingIds in
                    if meetingIds.count == 1, let single = meetingIds.first {
                        sidebarViewModel.moveMeeting(id: single, toProjectId: row.id)
                    } else {
                        sidebarViewModel.moveMeetings(ids: meetingIds, toProjectId: row.id)
                    }
                }
            )
        }
    }

    private func projectRenameField(_ row: FlatProjectRow) -> some View {
        TextField(L10n.projectName, text: $editingName)
            .textFieldStyle(.roundedBorder)
            .focused(isRenameFocused)
            .onSubmit { commitRename(row: row) }
            .onExitCommand { editingProjectId = nil }
            .onChange(of: isRenameFocused.wrappedValue) { _, focused in
                if !focused { commitRename(row: row) }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                isRenameFocused.wrappedValue = true
            }
    }

    private func selectRow(_ row: FlatProjectRow) {
        sidebarViewModel.selectProject(id: row.id, name: row.name)
    }

    private func commitRename(row: FlatProjectRow) {
        guard editingProjectId == row.id else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != row.displayName {
            let components = row.name.split(separator: "/")
            let newName: String = if components.count > 1 {
                components.dropLast().joined(separator: "/") + "/" + trimmed
            } else {
                trimmed
            }
            sidebarViewModel.renameProject(id: row.id, name: row.name, newName: newName)
        }
        editingProjectId = nil
    }
}

// MARK: - Sub-Views

/// プロジェクトヘッダー行。
private struct ProjectHeaderRow: View {
    let row: FlatProjectRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onEditContext: () -> Void
    let onOpenInFinder: () -> Void
    let onDelete: () -> Void
    let onRecreateFolder: () -> Void
    let onDropMeetings: (Set<UUID>) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    if row.missingOnDisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Image(systemName: row.missingOnDisk ? "folder.badge.questionmark" : "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? .primary : .tertiary)
                    Text(row.displayName)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            isDropTargeted
                ? Color.accentColor.opacity(0.1)
                : isSelected ? Color.primary.opacity(0.06) : Color.clear
        )
        .dropDestination(for: String.self) { items, _ in
            let ids: Set<UUID> = Set(
                items
                    .flatMap { $0.split(separator: "\n").map(String.init) }
                    .compactMap { UUID(uuidString: $0) }
            )
            guard !ids.isEmpty else { return false }
            onDropMeetings(ids)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .contextMenu {
            if row.missingOnDisk {
                Button(L10n.recreateFolder) { onRecreateFolder() }
                Divider()
            }
            Button(L10n.rename) { onRename() }
            if !row.missingOnDisk {
                Button(L10n.editContext) { onEditContext() }
                Button(L10n.openInFinder) { onOpenInFinder() }
            }
            Divider()
            Button(L10n.delete, role: .destructive) { onDelete() }
        }
        .help(row.missingOnDisk ? L10n.folderMissing : "")
    }
}

/// 保管庫切り替えメニュー。
private struct VaultMenuButton: View {
    let currentVault: VaultRecord?
    let allVaults: [VaultRecord]
    let onSelectVault: (VaultRecord) -> Void
    let onManageVaults: () -> Void

    var body: some View {
        Menu {
            ForEach(allVaults) { vault in
                Button {
                    onSelectVault(vault)
                } label: {
                    if currentVault?.id == vault.id {
                        Label(vault.name, systemImage: "checkmark")
                    } else {
                        Text(vault.name)
                    }
                }
            }

            Divider()

            Button(L10n.manageVaults, action: onManageVaults)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(currentVault?.name ?? L10n.vault)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .help(L10n.switchVault)
    }
}
