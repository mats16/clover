import SwiftUI

/// プロジェクト・文字起こし一覧を表示するサイドバー。
struct SidebarView: View {
    @ObservedObject var viewModel: CaptionViewModel
    @Bindable var sidebarViewModel: SidebarViewModel
    var columnVisibility: NavigationSplitViewVisibility = .all
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var editingProjectId: UUID?
    @State private var editingName = ""
    @State private var editingTranscriptionId: UUID?
    @State private var editingTranscriptionTitle = ""
    @State private var showNewProjectField = false
    @State private var newProjectName = ""
    @FocusState private var isRenameFocused: Bool
    @FocusState private var isTranscriptionRenameFocused: Bool
    @State private var isSettingsHovered = false

    var body: some View {
        sidebarContent
            .listStyle(.sidebar)
            .navigationTitle("")
            .toolbar {
                if columnVisibility != .detailOnly {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: { showNewProjectField = true }) {
                            Label(L10n.newProject, systemImage: "folder.badge.plus")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if showNewProjectField {
                    newProjectInputField
                }
            }
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
            .onChange(of: sidebarViewModel.selectedTranscriptionId) { _, newId in
                handleTranscriptionSelection(newId)
            }
            .alert("エラー", isPresented: Binding(
                get: { sidebarViewModel.lastError != nil },
                set: { if !$0 { sidebarViewModel.lastError = nil } }
            )) {
                Button("OK") { sidebarViewModel.lastError = nil }
            } message: {
                Text(sidebarViewModel.lastError ?? "")
            }
    }

    private var sidebarContent: some View {
        let selectedProjectId = sidebarViewModel.selectedProject?.id
        let transcriptions = sidebarViewModel.transcriptionsForSelectedProject
        let currentSelectedTranscriptionId = sidebarViewModel.selectedTranscriptionId

        return List(selection: $sidebarViewModel.selectedTranscriptionId) {
            ForEach(sidebarViewModel.flatProjects) { row in
                let isSelected = selectedProjectId == row.id
                ProjectSectionView(
                    row: row,
                    isSelected: isSelected,
                    transcriptions: isSelected ? transcriptions : [],
                    selectedTranscriptionId: currentSelectedTranscriptionId,
                    sidebarViewModel: sidebarViewModel,
                    viewModel: viewModel,
                    editingProjectId: $editingProjectId,
                    editingName: $editingName,
                    editingTranscriptionId: $editingTranscriptionId,
                    editingTranscriptionTitle: $editingTranscriptionTitle,
                    isRenameFocused: $isRenameFocused,
                    isTranscriptionRenameFocused: $isTranscriptionRenameFocused
                )
            }
        }
    }

    // MARK: - New Project Input

    private var newProjectInputField: some View {
        HStack {
            TextField(L10n.projectName, text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { createNewProject() }
            Button(L10n.create) { createNewProject() }
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button {
                showNewProjectField = false
                newProjectName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }

    // MARK: - Sidebar Footer

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                VaultMenuButton(
                    currentVault: sidebarViewModel.currentVault,
                    allVaults: sidebarViewModel.allVaults,
                    onSelectVault: onSelectVault,
                    onManageVaults: { openWindow(id: WindowID.vaultManager) }
                )

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSettingsHovered ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { isSettingsHovered = $0 }
                .help(L10n.settings)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Actions

    private func createNewProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        sidebarViewModel.createProject(name: name)
        newProjectName = ""
        showNewProjectField = false
    }

    private func handleTranscriptionSelection(_ transcriptionId: UUID?) {
        guard let transcriptionId else {
            viewModel.clearCurrentTranscription()
            return
        }
        if viewModel.isListening, viewModel.currentTranscriptionId == transcriptionId { return }
        guard !viewModel.isListening else { return }

        guard let dbQueue = sidebarViewModel.dbQueue,
              let projectURL = sidebarViewModel.selectedProjectURL,
              let project = sidebarViewModel.selectedProject,
              let vaultURL = sidebarViewModel.currentVault?.url else { return }
        viewModel.loadTranscription(
            transcriptionId,
            dbQueue: dbQueue,
            projectURL: projectURL,
            projectId: project.id,
            projectName: project.name,
            vaultURL: vaultURL
        )
    }
}

// MARK: - Project Section (独立 observation scope)

/// プロジェクト1行分の Section。独立した View として observation scope を分離し、
/// 選択変更時に全プロジェクト行が再評価されることを防ぐ。
private struct ProjectSectionView: View {
    let row: FlatProjectRow
    let isSelected: Bool
    let transcriptions: [TranscriptionRecord]
    let selectedTranscriptionId: UUID?
    let sidebarViewModel: SidebarViewModel
    let viewModel: CaptionViewModel
    @Binding var editingProjectId: UUID?
    @Binding var editingName: String
    @Binding var editingTranscriptionId: UUID?
    @Binding var editingTranscriptionTitle: String
    var isRenameFocused: FocusState<Bool>.Binding
    var isTranscriptionRenameFocused: FocusState<Bool>.Binding

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    var body: some View {
        Section {
            if isSelected {
                ForEach(transcriptions, id: \.id) { transcription in
                    transcriptionRow(transcription)
                        .tag(transcription.id)
                        .draggable(transcription.id.uuidString)
                        .contextMenu {
                            transcriptionContextMenu(transcription)
                        }
                }
            }
        } header: {
            projectHeader(row, isSelected: isSelected)
                .padding(.bottom, 4)
                .padding(.leading, CGFloat(row.depth) * 12)
        }
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
                onDoubleClick: {
                    editingName = row.displayName
                    editingProjectId = row.id
                },
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
                onDropTranscription: { transcriptionId in
                    sidebarViewModel.moveTranscription(id: transcriptionId, toProjectId: row.id)
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
        viewModel.clearCurrentTranscription()
    }

    // MARK: - Transcription Row

    @ViewBuilder
    private func transcriptionRow(_ transcription: TranscriptionRecord) -> some View {
        if editingTranscriptionId == transcription.id {
            TextField(L10n.title, text: $editingTranscriptionTitle)
                .textFieldStyle(.roundedBorder)
                .focused(isTranscriptionRenameFocused)
                .onSubmit { commitTranscriptionRename(id: transcription.id) }
                .onExitCommand { editingTranscriptionId = nil }
                .onChange(of: isTranscriptionRenameFocused.wrappedValue) { _, focused in
                    if !focused { commitTranscriptionRename(id: transcription.id) }
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(50))
                    isTranscriptionRenameFocused.wrappedValue = true
                }
        } else {
            TranscriptionListRow(
                transcription: transcription,
                isSelected: selectedTranscriptionId == transcription.id,
                dateFormatter: Self.dateFormatter,
                durationFormatter: Self.durationFormatter
            )
        }
    }

    @ViewBuilder
    private func transcriptionContextMenu(_ transcription: TranscriptionRecord) -> some View {
        Button(L10n.rename) {
            editingTranscriptionTitle = transcription.title
            editingTranscriptionId = transcription.id
        }
        Divider()
        Button(L10n.delete, role: .destructive) {
            sidebarViewModel.deleteTranscription(id: transcription.id)
        }
    }

    // MARK: - Rename Commits

    private func commitTranscriptionRename(id: UUID) {
        guard editingTranscriptionId == id else { return }
        let trimmed = editingTranscriptionTitle.trimmingCharacters(in: .whitespaces)
        sidebarViewModel.renameTranscription(id: id, newTitle: trimmed)
        editingTranscriptionId = nil
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

// MARK: - Hoverable Sub-Views

/// ホバー対応のプロジェクトヘッダー行。
private struct ProjectHeaderRow: View {
    let row: FlatProjectRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onRename: () -> Void
    let onEditContext: () -> Void
    let onOpenInFinder: () -> Void
    let onDelete: () -> Void
    let onDropTranscription: (UUID) -> Void
    @State private var isHovered = false
    @State private var isDropTargeted = false

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .foregroundColor(isSelected ? .accentColor : .secondary)
            Text(row.displayName)
                .font(.headline)
                .foregroundColor(isSelected ? .primary : isHovered ? .primary : .secondary)
            Spacer()
            if isSelected, !row.hasChildren {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isDropTargeted
                        ? Color.accentColor.opacity(0.2)
                        : isSelected
                            ? Color.accentColor.opacity(0.12)
                            : isHovered ? Color.primary.opacity(0.06) : Color.clear
                )
        )
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture(count: 1) { onSelect() }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let transcriptionId = UUID(uuidString: first) else {
                return false
            }
            onDropTranscription(transcriptionId)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .contextMenu {
            Button(L10n.rename) { onRename() }
            Button(L10n.editContext) { onEditContext() }
            Button(L10n.openInFinder) { onOpenInFinder() }
            Divider()
            Button(L10n.delete, role: .destructive) { onDelete() }
        }
    }
}

/// ホバー対応の文字起こし一覧行。
private struct TranscriptionListRow: View {
    let transcription: TranscriptionRecord
    let isSelected: Bool
    let dateFormatter: DateFormatter
    let durationFormatter: DateComponentsFormatter
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: transcription.endedAt != nil ? "waveform" : "record.circle.fill")
                    .font(.caption)
                    .foregroundColor(transcription.endedAt != nil ? .secondary : .red)
                if transcription.title.isEmpty {
                    Text(dateFormatter.string(from: transcription.startedAt))
                        .font(.subheadline)
                } else {
                    Text(transcription.title)
                        .font(.subheadline)
                }
            }
            HStack(spacing: 8) {
                if !transcription.title.isEmpty {
                    Text(dateFormatter.string(from: transcription.startedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let endedAt = transcription.endedAt {
                    let duration = endedAt.timeIntervalSince(transcription.startedAt)
                    Text(durationFormatter.string(from: duration) ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && !isSelected ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

/// ホバー対応の保管庫切り替えメニュー。
private struct VaultMenuButton: View {
    let currentVault: VaultRecord?
    let allVaults: [VaultRecord]
    let onSelectVault: (VaultRecord) -> Void
    let onManageVaults: () -> Void
    @State private var isHovered = false

    var body: some View {
        Menu {
            Picker(selection: Binding(
                get: { currentVault?.id },
                set: { newId in
                    if let vault = allVaults.first(where: { $0.id == newId }) {
                        onSelectVault(vault)
                    }
                }
            )) {
                ForEach(allVaults) { vault in
                    Text(vault.name).tag(UUID?.some(vault.id))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button(L10n.manageVaults) {
                onManageVaults()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(currentVault?.name ?? L10n.vault)
                    .font(.callout.bold())
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .help(L10n.switchVault)
    }
}
