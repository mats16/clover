import SwiftUI

/// プロジェクト・文字起こし一覧を表示するサイドバー。
struct SidebarView: View {
    @ObservedObject var viewModel: CaptionViewModel
    @ObservedObject var sidebarViewModel: SidebarViewModel
    var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editingProjectURL: URL?
    @State private var editingName: String = ""
    @State private var editingTranscriptionId: UUID?
    @State private var editingTranscriptionTitle: String = ""
    @State private var showNewProjectField: Bool = false
    @State private var newProjectName: String = ""
    @FocusState private var isRenameFocused: Bool
    @FocusState private var isTranscriptionRenameFocused: Bool

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
        List(selection: $sidebarViewModel.selectedTranscriptionId) {
            ForEach(sidebarViewModel.projects) { project in
                projectSection(project)
            }
        }
        .listStyle(.sidebar)
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
        .onChange(of: sidebarViewModel.selectedTranscriptionId) { _, newId in
            handleTranscriptionSelection(newId)
        }
    }

    // MARK: - Project Section

    @ViewBuilder
    private func projectSection(_ project: FolderProject) -> some View {
        Section {
            let transcriptions = sidebarViewModel.transcriptionsForSelectedProject.filter { _ in
                sidebarViewModel.selectedProject?.url == project.url
            }
            if sidebarViewModel.selectedProject?.url == project.url {
                ForEach(transcriptions, id: \.id) { transcription in
                    transcriptionRow(transcription)
                        .tag(transcription.id)
                        .contextMenu {
                            Button(L10n.rename) {
                                editingTranscriptionTitle = transcription.title
                                editingTranscriptionId = transcription.id
                            }
                            Divider()
                            Button(L10n.delete, role: .destructive) {
                                sidebarViewModel.deleteTranscription(id: transcription.id)
                            }
                        }
                }
            }
        } header: {
            projectHeader(project)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func projectHeader(_ project: FolderProject) -> some View {
        let isSelected = sidebarViewModel.selectedProject?.url == project.url

        if editingProjectURL == project.url {
            TextField(L10n.projectName, text: $editingName)
                .textFieldStyle(.roundedBorder)
                .focused($isRenameFocused)
                .onSubmit {
                    commitRename(project: project)
                }
                .onExitCommand {
                    editingProjectURL = nil
                }
                .onChange(of: isRenameFocused) { _, focused in
                    if !focused {
                        commitRename(project: project)
                    }
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(50))
                    isRenameFocused = true
                }
        } else {
            ProjectHeaderRow(
                project: project,
                isSelected: isSelected,
                onSelect: {
                    sidebarViewModel.selectProject(project)
                    viewModel.clearCurrentTranscription()
                },
                onDoubleClick: {
                    editingName = project.name
                    editingProjectURL = project.url
                },
                onRename: {
                    editingName = project.name
                    editingProjectURL = project.url
                },
                onEditReadme: {
                    sidebarViewModel.openReadme(for: project)
                },
                onDelete: {
                    sidebarViewModel.deleteProject(project)
                }
            )
        }
    }

    // MARK: - Transcription Row

    @ViewBuilder
    private func transcriptionRow(_ transcription: TranscriptionRecord) -> some View {
        if editingTranscriptionId == transcription.id {
            TextField(L10n.title, text: $editingTranscriptionTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isTranscriptionRenameFocused)
                .onSubmit {
                    commitTranscriptionRename(id: transcription.id)
                }
                .onExitCommand {
                    editingTranscriptionId = nil
                }
                .onChange(of: isTranscriptionRenameFocused) { _, focused in
                    if !focused {
                        commitTranscriptionRename(id: transcription.id)
                    }
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(50))
                    isTranscriptionRenameFocused = true
                }
        } else {
            TranscriptionListRow(
                transcription: transcription,
                isSelected: sidebarViewModel.selectedTranscriptionId == transcription.id,
                dateFormatter: Self.dateFormatter,
                durationFormatter: Self.durationFormatter
            )
        }
    }

    private func commitTranscriptionRename(id: UUID) {
        guard editingTranscriptionId == id else { return }
        let trimmed = editingTranscriptionTitle.trimmingCharacters(in: .whitespaces)
        sidebarViewModel.renameTranscription(id: id, newTitle: trimmed)
        editingTranscriptionId = nil
    }

    private func commitRename(project: FolderProject) {
        guard editingProjectURL == project.url else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != project.name {
            sidebarViewModel.renameProject(project, newName: trimmed)
        }
        editingProjectURL = nil
    }

    // MARK: - New Project Input

    private var newProjectInputField: some View {
        HStack {
            TextField(L10n.projectName, text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    createNewProject()
                }
            Button(L10n.create) {
                createNewProject()
            }
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
        if viewModel.isListening && viewModel.currentTranscriptionId == transcriptionId { return }
        guard !viewModel.isListening else { return }

        guard let dbQueue = sidebarViewModel.dbQueue else { return }
        viewModel.loadTranscription(transcriptionId, dbQueue: dbQueue)
    }
}

// MARK: - Hoverable Sub-Views

/// ホバー対応のプロジェクトヘッダー行。
private struct ProjectHeaderRow: View {
    let project: FolderProject
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onRename: () -> Void
    let onEditReadme: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .foregroundColor(isSelected ? .accentColor : .secondary)
            Text(project.name)
                .font(.headline)
                .foregroundColor(isSelected ? .primary : isHovered ? .primary : .secondary)
            Spacer()
            if isSelected {
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
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : isHovered ? Color.primary.opacity(0.06) : Color.clear
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture(count: 1) { onSelect() }
        .contextMenu {
            Button(L10n.rename) { onRename() }
            Button(L10n.editReadme) { onEditReadme() }
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
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && !isSelected ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}
