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
        let currentSelectedTranscriptionId = sidebarViewModel.selectedTranscriptionId

        return List {
            ForEach(sidebarViewModel.visibleFlatProjects) { row in
                let isSelected = selectedProjectId == row.id
                let isExpanded = !sidebarViewModel.isCollapsed(name: row.name)
                ProjectSectionView(
                    row: row,
                    isSelected: isSelected,
                    isExpanded: isExpanded,
                    transcriptions: isExpanded ? (sidebarViewModel.transcriptionsForProject[row.id] ?? []) : [],
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
                .textFieldStyle(.plain)
                .onSubmit { createNewProject() }
            Button(L10n.create) { createNewProject() }
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button {
                showNewProjectField = false
                newProjectName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
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

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L10n.settings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .rect)
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

// MARK: - Sidebar List Row Style

private extension View {
    func sidebarCompactRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

// MARK: - Project Section (独立 observation scope)

/// プロジェクト1行分の Section。独立した View として observation scope を分離し、
/// 選択変更時に全プロジェクト行が再評価されることを防ぐ。
private struct ProjectSectionView: View {
    let row: FlatProjectRow
    let isSelected: Bool
    let isExpanded: Bool
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

    private static let indentUnit: CGFloat = 12

    /// transcript が選択されていないときだけフォルダをハイライトする。
    private var isFolderHighlighted: Bool {
        isSelected && selectedTranscriptionId == nil
    }

    var body: some View {
        projectHeader(row, isSelected: isFolderHighlighted)
            .padding(.leading, CGFloat(row.depth) * Self.indentUnit)
            .sidebarCompactRow()
        if isExpanded {
            ForEach(transcriptions, id: \.id) { transcription in
                let isActive = selectedTranscriptionId == transcription.id
                transcriptionRow(transcription)
                    .padding(.leading, CGFloat(row.depth + 1) * Self.indentUnit)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .sidebarCompactRow()
                    .onTapGesture {
                        sidebarViewModel.ensureProjectSelected(id: row.id, name: row.name)
                        sidebarViewModel.selectedTranscriptionId = transcription.id
                    }
                    .accessibilityAddTraits(.isButton)
                    .draggable(transcription.id.uuidString)
                    .contextMenu {
                        transcriptionContextMenu(transcription)
                    }
            }
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
                isCollapsed: sidebarViewModel.isCollapsed(name: row.name),
                onSelect: { selectRow(row) },
                onToggleCollapse: { sidebarViewModel.toggleCollapse(name: row.name) },
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

// MARK: - Sub-Views

/// プロジェクトヘッダー行。
private struct ProjectHeaderRow: View {
    let row: FlatProjectRow
    let isSelected: Bool
    let isCollapsed: Bool
    let onSelect: () -> Void
    let onToggleCollapse: () -> Void
    let onRename: () -> Void
    let onEditContext: () -> Void
    let onOpenInFinder: () -> Void
    let onDelete: () -> Void
    let onRecreateFolder: () -> Void
    let onDropTranscription: (UUID) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        HStack {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .animation(.easeInOut(duration: 0.15), value: isCollapsed)
                .frame(width: 10)
                .contentShape(Rectangle())
                .onTapGesture { onToggleCollapse() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isCollapsed ? L10n.expand : L10n.collapse)
            if row.missingOnDisk {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            Image(systemName: row.missingOnDisk ? "folder.badge.questionmark" : "folder")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(row.displayName)
                .font(.body)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isDropTargeted
                        ? Color.accentColor.opacity(0.2)
                        : isSelected ? Color.accentColor.opacity(0.12) : Color.clear
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .accessibilityAddTraits(.isButton)
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

/// 文字起こし一覧行。
private struct TranscriptionListRow: View {
    let transcription: TranscriptionRecord
    let dateFormatter: DateFormatter
    let durationFormatter: DateComponentsFormatter

    var body: some View {
        HStack {
            if transcription.endedAt != nil {
                Image(systemName: "waveform")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "record.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            Text(dateFormatter.string(from: transcription.startedAt))
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize()
            if !transcription.title.isEmpty {
                Text(transcription.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let endedAt = transcription.endedAt {
                let minutes = Int(endedAt.timeIntervalSince(transcription.startedAt) / 60)
                Text("\(minutes)分")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
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
                    .font(.body.weight(.medium))
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
