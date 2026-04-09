import Foundation
import GRDB
import Observation
import SwiftUI

/// サイドバーの状態管理。DB 駆動の階層プロジェクトツリーと文字起こし一覧を管理する。
@Observable
@MainActor
final class SidebarViewModel {

    // MARK: - Observed State

    var flatProjects: [FlatProjectRow] = []
    var selectedProject: ProjectRecord?
    var selectedTranscriptionId: UUID?
    var transcriptionsForSelectedProject: [TranscriptionRecord] = []
    var lastError: String?
    var allVaults: [VaultRecord] = []

    // MARK: - Active Database & Vault

    @ObservationIgnored private(set) var appDatabase: AppDatabaseManager?
    /// 現在の保管庫。AppSettings.shared.currentVault から委譲。
    var currentVault: VaultRecord? { AppSettings.shared.currentVault }
    var dbQueue: DatabaseQueue? { appDatabase?.dbQueue }

    /// プロジェクト名から vault 内の URL を返す。
    func projectURL(for name: String) -> URL {
        currentVault!.url.appendingPathComponent(name, isDirectory: true)
    }

    /// 現在選択中のプロジェクトの vault 内 URL。
    var selectedProjectURL: URL? {
        guard let name = selectedProject?.name else { return nil }
        return projectURL(for: name)
    }

    @ObservationIgnored private let folderService = FolderProjectService()
    @ObservationIgnored private var transcriptionRepository: TranscriptionRepository?
    @ObservationIgnored private var fileWatcher: TranscriptFileWatcher?
    @ObservationIgnored private var transcriptionObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var projectObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var vaultObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var vaultSyncService: VaultSyncService?

    /// 保管庫の最終オープン日時を更新する。
    func updateVaultLastOpened(_ id: UUID) {
        try? transcriptionRepository?.updateVaultLastOpened(id: id)
    }

    /// アプリ起動時に AppDatabaseManager と保管庫を設定する。
    /// 呼び出し前に AppSettings.shared.currentVault を設定しておくこと。
    func setAppDatabase(_ database: AppDatabaseManager?) {
        appDatabase = database
        transcriptionRepository = database.map { TranscriptionRepository(dbQueue: $0.dbQueue) }

        // 既存の監視を停止
        vaultSyncService?.stopMonitoring()
        projectObservation?.cancel()
        vaultObservation?.cancel()
        fileWatcher?.stopMonitoring()

        // 選択状態をリセット
        selectedProject = nil
        selectedTranscriptionId = nil
        transcriptionsForSelectedProject = []
        transcriptionObservation = nil

        // vaults テーブルの ValueObservation で保管庫一覧を自動更新
        if let dbQueue = database?.dbQueue {
            let vaultObs = ValueObservation.tracking { db in
                try VaultRecord.order(Column("lastOpenedAt").desc).fetchAll(db)
            }
            vaultObservation = vaultObs.start(
                in: dbQueue,
                onError: { _ in },
                onChange: { [weak self] vaults in
                    Task { @MainActor in
                        guard let self, self.allVaults != vaults else { return }
                        self.allVaults = vaults
                    }
                }
            )
        }

        guard let dbQueue = database?.dbQueue,
              let vault = currentVault else {
            vaultSyncService = nil
            fileWatcher = nil
            flatProjects = []
            return
        }

        let vaultURL = vault.url
        let vaultId = vault.id

        // VaultSyncService: 初期同期（バックグラウンド） + FSEvents 監視
        let syncService = VaultSyncService(vaultURL: vaultURL, dbQueue: dbQueue, vaultId: vaultId)
        vaultSyncService = syncService
        Task.detached(priority: .userInitiated) {
            syncService.performInitialSync()
        }
        syncService.startMonitoring()

        // TranscriptFileWatcher: _transcripts/ ディレクトリの監視
        let watcher = TranscriptFileWatcher(dbQueue: dbQueue, vaultURL: vaultURL)
        watcher.startMonitoring()
        fileWatcher = watcher

        // projects テーブルの ValueObservation でツリーを自動更新（vaultId でフィルタ）
        let observation = ValueObservation.tracking { db in
            try ProjectRecord
                .filter(Column("vaultId") == vaultId)
                .order(Column("name").asc)
                .fetchAll(db)
        }
        projectObservation = observation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] records in
                Task { @MainActor in
                    guard let self else { return }
                    let rows = FlatProjectRow.buildRows(fromRecords: records)
                    guard self.flatProjects != rows else { return }
                    self.flatProjects = rows
                }
            }
        )
    }

    // MARK: - Selection

    func selectProject(id: UUID, name: String) {
        guard let vault = currentVault else { return }
        if selectedProject?.id == id {
            selectedTranscriptionId = nil
            return
        }
        selectedProject = ProjectRecord(id: id, vaultId: vault.id, name: name, createdAt: .distantPast)
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
                    guard let self, self.transcriptionsForSelectedProject != transcriptions else { return }
                    self.transcriptionsForSelectedProject = transcriptions
                }
            }
        )
    }

    // MARK: - Project CRUD

    func createProject(name: String) {
        guard let vault = currentVault else { return }
        let projectURL = projectURL(for: name)
        do {
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let repo = transcriptionRepository else { return }
        // 中間パスの親プロジェクトを先に作成し、対象プロジェクトを fetchOrCreate で取得
        let intermediates = ProjectRecord.allIntermediatePaths(for: name).dropLast()
        if !intermediates.isEmpty {
            try? repo.upsertProjects(names: Array(intermediates), vaultId: vault.id)
        }
        if let record = try? repo.fetchOrCreateProject(name: name, vaultId: vault.id) {
            selectProject(id: record.id, name: record.name)
        }
    }

    func renameProject(id: UUID, name: String, newName: String) {
        guard let vault = currentVault else { return }
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

        try? transcriptionRepository?.renameProjectsByPrefix(oldPrefix: name, newPrefix: newName, vaultId: vault.id)

        if isActive, let updated = try? transcriptionRepository?.fetchOrCreateProject(name: newName, vaultId: vault.id) {
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
        guard let vault = currentVault else { return }
        let projectURL = projectURL(for: name)

        if let selected = selectedProject,
           selected.id == id || selected.name.hasPrefix(name + "/") {
            selectedProject = nil
            selectedTranscriptionId = nil
            transcriptionsForSelectedProject = []
            transcriptionObservation = nil
        }

        // FS 削除を先に実行 — フォルダが既に存在しない場合はスキップ
        if FileManager.default.fileExists(atPath: projectURL.path) {
            do {
                try FileManager.default.trashItem(at: projectURL, resultingItemURL: nil)
            } catch {
                lastError = "フォルダの削除に失敗しました: \(error.localizedDescription)"
                return
            }
        }

        // FS 成功後に DB 削除（サブツリー対応）
        do {
            try transcriptionRepository?.deleteProjectsByPrefix(name: name, vaultId: vault.id)
        } catch {
            lastError = "データベースの更新に失敗しました: \(error.localizedDescription)"
        }
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

    func moveTranscription(id: UUID, toProjectId: UUID) {
        guard let repo = transcriptionRepository else { return }
        do {
            try repo.moveTranscription(id: id, toProjectId: toProjectId)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
