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
    /// 複数選択中の文字起こし ID。
    var selectedTranscriptionIds: Set<UUID> = []
    /// 展開中のプロジェクトごとの文字起こし一覧（プロジェクトID → レコード配列）。
    var transcriptionsForProject: [UUID: [TranscriptionRecord]] = [:]
    var lastError: String?
    var allVaults: [VaultRecord] = []

    /// 後方互換: 選択中プロジェクトの文字起こし一覧。
    var transcriptionsForSelectedProject: [TranscriptionRecord] {
        guard let project = selectedProject else { return [] }
        return transcriptionsForProject[project.id] ?? []
    }

    // MARK: - Collapse State

    /// 折りたたまれているプロジェクト名のセット（UserDefaults で永続化）。
    /// 初期状態では全フォルダが折りたたまれる。ユーザーが明示的に展開したものは expandedProjectNames に記録される。
    var collapsedProjectNames: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "collapsedProjectNames") ?? []
        return Set(saved)
    }() {
        didSet {
            UserDefaults.standard.set(Array(collapsedProjectNames), forKey: "collapsedProjectNames")
        }
    }

    /// ユーザーが明示的に展開したプロジェクト名（UserDefaults で永続化）。
    /// この集合に含まれないフォルダは、hasChildren なら自動的に折りたたまれる。
    @ObservationIgnored private var expandedProjectNames: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "expandedProjectNames") ?? []
        return Set(saved)
    }()

    private func saveExpandedNames() {
        UserDefaults.standard.set(Array(expandedProjectNames), forKey: "expandedProjectNames")
    }

    /// flatProjects が更新されたとき、まだ操作されていない全フォルダを自動的に折りたたむ。
    func syncCollapseState() {
        var updated = collapsedProjectNames
        for row in flatProjects {
            if !expandedProjectNames.contains(row.name) {
                updated.insert(row.name)
            }
        }
        // 存在しなくなったフォルダを除外
        let allNames = Set(flatProjects.map(\.name))
        updated = updated.intersection(allNames)
        if updated != collapsedProjectNames {
            collapsedProjectNames = updated
        }
        refreshTranscriptionObservations()
    }

    /// 折りたたまれた祖先を持つ行を除外した、表示用プロジェクト一覧。
    var visibleFlatProjects: [FlatProjectRow] {
        guard !collapsedProjectNames.isEmpty else { return flatProjects }
        return flatProjects.filter { row in
            !row.parentPaths().contains(where: { collapsedProjectNames.contains($0) })
        }
    }

    /// フォルダの折りたたみ状態をトグルする。
    func toggleCollapse(name: String) {
        if collapsedProjectNames.contains(name) {
            // 展開
            collapsedProjectNames.remove(name)
            expandedProjectNames.insert(name)
            if let row = flatProjects.first(where: { $0.name == name }) {
                startTranscriptionObservation(projectId: row.id)
            }
        } else {
            // 折りたたみ
            collapsedProjectNames.insert(name)
            expandedProjectNames.remove(name)
            // 選択中プロジェクトの監視は維持
            if let row = flatProjects.first(where: { $0.name == name }),
               selectedProject?.id != row.id {
                stopTranscriptionObservation(projectId: row.id)
            }
        }
        saveExpandedNames()
    }

    /// 指定した名前のフォルダが折りたたまれているかどうか。
    func isCollapsed(name: String) -> Bool {
        collapsedProjectNames.contains(name)
    }

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
    @ObservationIgnored private var transcriptionObservations: [UUID: AnyDatabaseCancellable] = [:]
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

        // 全 transcription 監視を停止
        for (_, cancellable) in transcriptionObservations {
            cancellable.cancel()
        }
        transcriptionObservations.removeAll()
        transcriptionsForProject.removeAll()

        // 選択状態をリセット
        selectedProject = nil
        selectedTranscriptionId = nil
        selectedTranscriptionIds.removeAll()

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
                    self.syncCollapseState()
                }
            }
        )
    }

    // MARK: - Selection

    func selectProject(id: UUID, name: String) {
        guard let vault = currentVault else { return }
        // 折りたたまれていたら展開する
        if collapsedProjectNames.contains(name) {
            collapsedProjectNames.remove(name)
            expandedProjectNames.insert(name)
            saveExpandedNames()
            startTranscriptionObservation(projectId: id)
        }
        if selectedProject?.id == id {
            selectedTranscriptionId = nil
            selectedTranscriptionIds.removeAll()
            return
        }
        // 旧選択プロジェクトが折りたたまれていれば監視を停止
        if let oldProject = selectedProject,
           collapsedProjectNames.contains(oldProject.name) {
            stopTranscriptionObservation(projectId: oldProject.id)
        }
        selectedProject = ProjectRecord(id: id, vaultId: vault.id, name: name, createdAt: .distantPast)
        selectedTranscriptionId = nil
        selectedTranscriptionIds.removeAll()
        startTranscriptionObservation(projectId: id)
    }

    /// transcript クリック時にプロジェクトを選択状態にする（selectedTranscriptionId を触らない）。
    func ensureProjectSelected(id: UUID, name: String) {
        guard let vault = currentVault else { return }
        if collapsedProjectNames.contains(name) {
            collapsedProjectNames.remove(name)
            expandedProjectNames.insert(name)
            saveExpandedNames()
            startTranscriptionObservation(projectId: id)
        }
        guard selectedProject?.id != id else { return }
        if let oldProject = selectedProject,
           collapsedProjectNames.contains(oldProject.name) {
            stopTranscriptionObservation(projectId: oldProject.id)
        }
        selectedProject = ProjectRecord(id: id, vaultId: vault.id, name: name, createdAt: .distantPast)
        startTranscriptionObservation(projectId: id)
    }

    func selectTranscription(_ id: UUID) {
        selectedTranscriptionId = id
    }

    // MARK: - Transcription Observation

    /// 指定プロジェクトの文字起こし監視を開始する。
    func startTranscriptionObservation(projectId: UUID) {
        guard let dbQueue, transcriptionObservations[projectId] == nil else { return }

        let observation = ValueObservation.tracking { db in
            try TranscriptionRecord
                .filter(Column("projectId") == projectId)
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }

        transcriptionObservations[projectId] = observation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] transcriptions in
                Task { @MainActor in
                    guard let self else { return }
                    self.transcriptionsForProject[projectId] = transcriptions
                }
            }
        )
    }

    /// 指定プロジェクトの文字起こし監視を停止する。
    func stopTranscriptionObservation(projectId: UUID) {
        transcriptionObservations[projectId]?.cancel()
        transcriptionObservations.removeValue(forKey: projectId)
        transcriptionsForProject.removeValue(forKey: projectId)
    }

    /// 展開状態と選択状態に基づいて文字起こし監視を同期する。
    private func refreshTranscriptionObservations() {
        let expandedIds = Set(
            flatProjects
                .filter { !collapsedProjectNames.contains($0.name) }
                .map(\.id)
        )
        let selectedId = selectedProject?.id
        let requiredIds = expandedIds.union(selectedId.map { [$0] } ?? [])

        // 不要な監視を停止
        for id in transcriptionObservations.keys where !requiredIds.contains(id) {
            stopTranscriptionObservation(projectId: id)
        }
        // 必要な監視を開始
        for id in requiredIds {
            startTranscriptionObservation(projectId: id)
        }
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
        }
        stopTranscriptionObservation(projectId: id)

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
        }
        // 削除対象プロジェクトの transcription 監視を停止
        stopTranscriptionObservation(projectId: id)

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

    /// ディスクにフォルダを再作成し、missingOnDisk フラグをクリアする。
    func recreateFolder(name: String) {
        guard let vault = currentVault else { return }
        let url = projectURL(for: name)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try transcriptionRepository?.clearProjectsMissing(prefix: name, vaultId: vault.id)
        } catch {
            lastError = "フォルダの再作成に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Transcription Management

    func renameTranscription(id: UUID, newTitle: String) {
        try? transcriptionRepository?.renameTranscription(id: id, newTitle: newTitle)
    }

    func deleteTranscription(id: UUID) {
        try? transcriptionRepository?.deleteTranscription(id: id)
        selectedTranscriptionIds.remove(id)
        if selectedTranscriptionId == id {
            selectedTranscriptionId = nil
        }
    }

    /// 複数の文字起こしを一括削除する。
    func deleteTranscriptions(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        do {
            try transcriptionRepository?.deleteTranscriptions(ids: ids)
        } catch {
            lastError = error.localizedDescription
            return
        }
        if let selected = selectedTranscriptionId, ids.contains(selected) {
            selectedTranscriptionId = nil
        }
        selectedTranscriptionIds.subtract(ids)
    }

    func moveTranscription(id: UUID, toProjectId: UUID) {
        guard let repo = transcriptionRepository else { return }
        do {
            try repo.moveTranscription(id: id, toProjectId: toProjectId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 複数の文字起こしを一括移動する。
    func moveTranscriptions(ids: Set<UUID>, toProjectId: UUID) {
        guard let repo = transcriptionRepository, !ids.isEmpty else { return }
        do {
            try repo.moveTranscriptions(ids: ids, toProjectId: toProjectId)
        } catch {
            lastError = error.localizedDescription
            return
        }
        selectedTranscriptionIds.removeAll()
    }

    // MARK: - Multi-Selection Helpers

    /// Cmd+Click: トグル選択。
    func toggleTranscriptionSelection(_ id: UUID, projectId: UUID, projectName: String) {
        ensureProjectSelected(id: projectId, name: projectName)
        if selectedTranscriptionIds.contains(id) {
            selectedTranscriptionIds.remove(id)
            // 最後の選択解除なら selectedTranscriptionId もクリア
            if selectedTranscriptionIds.isEmpty {
                selectedTranscriptionId = nil
            } else {
                selectedTranscriptionId = selectedTranscriptionIds.first
            }
        } else {
            selectedTranscriptionIds.insert(id)
            // 最初の追加なら既存の単一選択も含める
            if let existing = selectedTranscriptionId, existing != id {
                selectedTranscriptionIds.insert(existing)
            }
            selectedTranscriptionId = id
        }
    }

    /// Shift+Click: 範囲選択。
    func rangeSelectTranscription(_ id: UUID, projectId: UUID, projectName: String) {
        ensureProjectSelected(id: projectId, name: projectName)
        let transcriptions = transcriptionsForProject[projectId] ?? []
        guard let anchor = selectedTranscriptionId,
              let anchorIndex = transcriptions.firstIndex(where: { $0.id == anchor }),
              let targetIndex = transcriptions.firstIndex(where: { $0.id == id }) else {
            // anchor がない場合は単一選択にフォールバック
            selectedTranscriptionIds = [id]
            selectedTranscriptionId = id
            return
        }
        let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
        selectedTranscriptionIds = Set(transcriptions[range].map(\.id))
        selectedTranscriptionId = id
    }

    /// 通常クリック: 単一選択（複数選択をクリア）。
    func singleSelectTranscription(_ id: UUID, projectId: UUID, projectName: String) {
        ensureProjectSelected(id: projectId, name: projectName)
        selectedTranscriptionIds = [id]
        selectedTranscriptionId = id
    }

    /// 選択中の文字起こし ID を返す（単一選択時も含む）。
    var effectiveSelectedIds: Set<UUID> {
        if selectedTranscriptionIds.isEmpty, let single = selectedTranscriptionId {
            return [single]
        }
        return selectedTranscriptionIds
    }
}
