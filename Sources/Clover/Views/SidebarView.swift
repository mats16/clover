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
            HStack {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(project.name)
                    .font(.headline)
                    .foregroundColor(isSelected ? .primary : .secondary)
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
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                editingName = project.name
                editingProjectURL = project.url
            }
            .onTapGesture(count: 1) {
                sidebarViewModel.selectProject(project)
                viewModel.clearCurrentTranscription()
            }
            .contextMenu {
                Button(L10n.rename) {
                    editingName = project.name
                    editingProjectURL = project.url
                }
                Button(L10n.editReadme) {
                    sidebarViewModel.openReadme(for: project)
                }
                Divider()
                Button(L10n.delete, role: .destructive) {
                    sidebarViewModel.deleteProject(project)
                }
            }
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
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: transcription.endedAt != nil ? "waveform" : "record.circle.fill")
                        .font(.caption)
                        .foregroundColor(transcription.endedAt != nil ? .secondary : .red)
                    if transcription.title.isEmpty {
                        Text(Self.dateFormatter.string(from: transcription.startedAt))
                            .font(.subheadline)
                    } else {
                        Text(transcription.title)
                            .font(.subheadline)
                    }
                }
                HStack(spacing: 8) {
                    if !transcription.title.isEmpty {
                        Text(Self.dateFormatter.string(from: transcription.startedAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let endedAt = transcription.endedAt {
                        let duration = endedAt.timeIntervalSince(transcription.startedAt)
                        Text(Self.durationFormatter.string(from: duration) ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
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
