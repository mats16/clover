import Foundation
import SwiftUI
import Combine
import GRDB

/// サイドバーの状態管理。フォルダベースのプロジェクトと文字起こしの一覧・選択を管理する。
@MainActor
final class SidebarViewModel: ObservableObject {
    // MARK: - Published State

    @Published var projects: [FolderProject] = []
    @Published var selectedProject: FolderProject?
    @Published var selectedTranscriptionId: UUID?
    @Published var transcriptionsForSelectedProject: [TranscriptionRecord] = []

    // MARK: - Active Database

    private(set) var activeDatabase: ProjectDatabaseManager?
    var dbQueue: DatabaseQueue? { activeDatabase?.dbQueue }

    private let folderService = FolderProjectService()
    private var vaultPathCancellable: AnyCancellable?
    private var transcriptionObservation: AnyDatabaseCancellable?

    init() {
        // 保管庫パスの変更を監視してプロジェクト一覧を再読み込み
        vaultPathCancellable = UserDefaults.standard
            .publisher(for: \.vaultPath)
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] (_: String?) in
                self?.handleVaultPathChanged()
            }
    }

    private func handleVaultPathChanged() {
        selectedProject = nil
        selectedTranscriptionId = nil
        transcriptionsForSelectedProject = []
        activeDatabase = nil
        transcriptionRepository = nil
        transcriptionObservation = nil
        loadProjects()
    }
    private var transcriptionRepository: TranscriptionRepository?

    // MARK: - Data Loading

    func loadProjects() {
        let vaultURL = AppSettings.shared.vaultURL
        projects = (try? folderService.fetchAllProjects(in: vaultURL)) ?? []
    }

    func selectProject(_ project: FolderProject) {
        guard selectedProject?.url != project.url else { return }
        selectedProject = project
        selectedTranscriptionId = nil
        do {
            activeDatabase = try ProjectDatabaseManager(projectURL: project.url)
            transcriptionRepository = dbQueue.map { TranscriptionRepository(dbQueue: $0) }
        } catch {
            activeDatabase = nil
            transcriptionRepository = nil
        }
        observeTranscriptions()
    }

    func selectTranscription(_ id: UUID) {
        selectedTranscriptionId = id
    }

    // MARK: - Transcription Observation

    private func observeTranscriptions() {
        transcriptionObservation?.cancel()
        guard let dbQueue else {
            transcriptionsForSelectedProject = []
            return
        }

        let observation = ValueObservation.tracking { db in
            try TranscriptionRecord
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }

        transcriptionObservation = observation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] transcriptions in
                Task { @MainActor in
                    self?.transcriptionsForSelectedProject = transcriptions
                }
            }
        )
    }

    // MARK: - Project CRUD

    func createProject(name: String) {
        let vaultURL = AppSettings.shared.vaultURL
        guard let project = try? folderService.createProject(named: name, in: vaultURL) else { return }
        loadProjects()
        selectProject(project)
    }

    func renameProject(_ project: FolderProject, newName: String) {
        let isActive = selectedProject?.url == project.url
        if isActive {
            activeDatabase = nil
            transcriptionRepository = nil
            transcriptionObservation = nil
        }

        guard let renamed = try? folderService.renameProject(project, to: newName) else {
            if isActive { selectProject(project) }
            return
        }

        loadProjects()
        if isActive {
            selectProject(renamed)
        }
    }

    /// README.md を作成（未存在の場合）し、設定されたエディタで開く。
    func openReadme(for project: FolderProject) {
        guard let readmeURL = try? folderService.ensureReadmeExists(for: project) else { return }
        AppSettings.shared.markdownEditor.open(readmeURL)
    }

    func deleteProject(_ project: FolderProject) {
        if selectedProject?.url == project.url {
            selectedProject = nil
            selectedTranscriptionId = nil
            transcriptionsForSelectedProject = []
            activeDatabase = nil
            transcriptionRepository = nil
            transcriptionObservation = nil
        }
        try? folderService.deleteProject(project)
        loadProjects()
    }

    // MARK: - Transcription Management

    func renameTranscription(id: UUID, newTitle: String) {
        try? transcriptionRepository?.renameTranscription(id: id, newTitle: newTitle)
    }

    func deleteTranscription(id: UUID) {
        try? transcriptionRepository?.deleteTranscription(id: id)
        if selectedTranscriptionId == id {
            selectedTranscriptionId = nil
        }
    }
}
