import Foundation
import SwiftUI
import Combine
import GRDB

/// サイドバーの状態管理。DB 駆動の階層プロジェクトツリーと文字起こし一覧を管理する。
@MainActor
final class SidebarViewModel: ObservableObject {
    // MARK: - Published State

    @Published var projectTree: [ProjectNode] = []
    @Published var flatProjects: [FlatProjectRow] = []
    @Published var selectedProject: ProjectRecord?
    @Published var selectedTranscriptionId: UUID?
    @Published var transcriptionsForSelectedProject: [TranscriptionRecord] = []

    // MARK: - Active Database

    private(set) var appDatabase: AppDatabaseManager?
    var dbQueue: DatabaseQueue? { appDatabase?.dbQueue }

    /// プロジェクト名から vault 内の URL を返す。
    func projectURL(for name: String) -> URL {
        AppSettings.shared.vaultURL.appendingPathComponent(name, isDirectory: true)
    }

    /// 現在選択中のプロジェクトの vault 内 URL。
    var selectedProjectURL: URL? {
        guard let name = selectedProject?.name else { return nil }
        return projectURL(for: name)
    }

    private let folderService = FolderProjectService()
    private var transcriptionRepository: TranscriptionRepository?
    private var fileWatcher: TranscriptFileWatcher?
    private var vaultPathCancellable: AnyCancellable?
    private var transcriptionObservation: AnyDatabaseCancellable?
    private var projectObservation: AnyDatabaseCancellable?
    private var vaultSyncService: VaultSyncService?

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

    /// アプリ起動時に AppDatabaseManager を設定する。
    func setAppDatabase(_ database: AppDatabaseManager?) {
        appDatabase = database
        transcriptionRepository = database.map { TranscriptionRepository(dbQueue: $0.dbQueue) }

        // 既存の監視を停止
        vaultSyncService?.stopMonitoring()
        projectObservation?.cancel()
        fileWatcher?.stopMonitoring()

        guard let dbQueue = database?.dbQueue else {
            vaultSyncService = nil
            fileWatcher = nil
            projectTree = []
            return
        }

        let vaultURL = AppSettings.shared.vaultURL

        // VaultSyncService: 初期同期（バックグラウンド） + FSEvents 監視
        let syncService = VaultSyncService(vaultURL: vaultURL, dbQueue: dbQueue)
        vaultSyncService = syncService
        Task.detached(priority: .userInitiated) {
            syncService.performInitialSync()
        }
        syncService.startMonitoring()

        // TranscriptFileWatcher: _transcripts/ ディレクトリの監視
        let watcher = TranscriptFileWatcher(dbQueue: dbQueue, vaultURL: vaultURL)
        watcher.startMonitoring()
        fileWatcher = watcher

        // projects テーブルの ValueObservation でツリーを自動更新
        let observation = ValueObservation.tracking { db in
            try ProjectRecord.order(Column("name").asc).fetchAll(db)
        }
        projectObservation = observation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] records in
                Task { @MainActor in
                    let tree = ProjectNode.buildTree(from: records)
                    self?.projectTree = tree
                    self?.flatProjects = ProjectNode.flatten(tree)
                }
            }
        )
    }

    private func handleVaultPathChanged() {
        selectedProject = nil
        selectedTranscriptionId = nil
        transcriptionsForSelectedProject = []
        transcriptionObservation = nil

        // 新しい vault パスで DB を再生成
        let vaultURL = AppSettings.shared.vaultURL
        do {
            let database = try AppDatabaseManager(vaultURL: vaultURL)
            setAppDatabase(database)
        } catch {
            setAppDatabase(nil)
        }
    }

    // MARK: - Selection

    func selectProject(id: UUID, name: String) {
        guard selectedProject?.id != id else { return }
        selectedProject = ProjectRecord(id: id, name: name, createdAt: .distantPast)
        selectedTranscriptionId = nil
        observeTranscriptions()
    }

    func selectTranscription(_ id: UUID) {
        selectedTranscriptionId = id
    }

    // MARK: - Transcription Observation

    private func observeTranscriptions() {
        transcriptionObservation?.cancel()
        guard let dbQueue, let project = selectedProject else {
            transcriptionsForSelectedProject = []
            return
        }

        let projectId = project.id
        let observation = ValueObservation.tracking { db in
            try TranscriptionRecord
                .filter(Column("projectId") == projectId)
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
        let projectURL = projectURL(for: name)
        do {
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let repo = transcriptionRepository else { return }
        try? repo.upsertProjects(names: ProjectRecord.allIntermediatePaths(for: name))

        if let record = try? repo.fetchOrCreateProject(name: name) {
            selectProject(id: record.id, name: record.name)
        }
    }

    func renameProject(id: UUID, name: String, newName: String) {
        let oldURL = projectURL(for: name)
        let newURL = projectURL(for: newName)

        let isActive = selectedProject?.id == id
        if isActive {
            selectedProject = nil
            transcriptionObservation = nil
        }

        do {
            try FileManager.default.createDirectory(
                at: newURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            if isActive { selectProject(id: id, name: name) }
            return
        }

        try? transcriptionRepository?.renameProjectsByPrefix(oldPrefix: name, newPrefix: newName)

        if isActive, let updated = try? transcriptionRepository?.fetchOrCreateProject(name: newName) {
            selectProject(id: updated.id, name: updated.name)
        }
    }

    /// CONTEXT.md を作成（未存在の場合）し、設定されたエディタで開く。
    func openContext(projectName: String) {
        let projectURL = projectURL(for: projectName)
        guard let contextURL = folderService.ensureContextFileExists(at: projectURL) else { return }
        AppSettings.shared.markdownEditor.open(contextURL)
    }

    func deleteProject(id: UUID, name: String) {
        let projectURL = projectURL(for: name)

        if selectedProject?.id == id {
            selectedProject = nil
            selectedTranscriptionId = nil
            transcriptionsForSelectedProject = []
            transcriptionObservation = nil
        }

        try? transcriptionRepository?.deleteProject(id: id)
        try? FileManager.default.trashItem(at: projectURL, resultingItemURL: nil)
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
