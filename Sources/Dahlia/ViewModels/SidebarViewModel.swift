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
    var selectedMeetingId: UUID?
    /// 複数選択中の文字起こし ID。
    var selectedMeetingIds: Set<UUID> = []
    /// 展開中のプロジェクトごとの文字起こし一覧（プロジェクトID → レコード配列）。
    var meetingsForProject: [UUID: [MeetingRecord]] = [:]
    var lastError: String?
    var allVaults: [VaultRecord] = []

    /// 後方互換: 選択中プロジェクトの文字起こし一覧。
    var meetingsForSelectedProject: [MeetingRecord] {
        guard let project = selectedProject else { return [] }
        return meetingsForProject[project.id] ?? []
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
        refreshMeetingObservations()
    }

    /// 折りたたまれた祖先を持つ行を除外した、表示用プロジェクト一覧。
    var visibleFlatProjects: [FlatProjectRow] {
        guard !collapsedProjectNames.isEmpty else { return flatProjects }
        return flatProjects.filter { row in
            !row.parentPaths().contains(where: { collapsedProjectNames.contains($0) })
        }
    }

    /// フォルダの折りたたみ状態をトグルする（サブフォルダの階層表示用）。
    func toggleCollapse(name: String) {
        if collapsedProjectNames.contains(name) {
            collapsedProjectNames.remove(name)
            expandedProjectNames.insert(name)
        } else {
            collapsedProjectNames.insert(name)
            expandedProjectNames.remove(name)
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
    @ObservationIgnored private var meetingRepository: MeetingRepository?
    @ObservationIgnored private var fileWatcher: TranscriptFileWatcher?
    @ObservationIgnored private var meetingObservations: [UUID: AnyDatabaseCancellable] = [:]
    @ObservationIgnored private var projectObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var vaultObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var vaultSyncService: VaultSyncService?

    /// 保管庫の最終オープン日時を更新する。
    func updateVaultLastOpened(_ id: UUID) {
        try? meetingRepository?.updateVaultLastOpened(id: id)
    }

    /// アプリ起動時に AppDatabaseManager と保管庫を設定する。
    /// 呼び出し前に AppSettings.shared.currentVault を設定しておくこと。
    func setAppDatabase(_ database: AppDatabaseManager?) {
        appDatabase = database
        meetingRepository = database.map { MeetingRepository(dbQueue: $0.dbQueue) }

        // 既存の監視を停止
        vaultSyncService?.stopMonitoring()
        projectObservation?.cancel()
        vaultObservation?.cancel()
        fileWatcher?.stopMonitoring()

        // 全 meeting 監視を停止
        for (_, cancellable) in meetingObservations {
            cancellable.cancel()
        }
        meetingObservations.removeAll()
        meetingsForProject.removeAll()

        // 選択状態をリセット
        selectedProject = nil
        selectedMeetingId = nil
        selectedMeetingIds.removeAll()

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
        if selectedProject?.id == id {
            selectedMeetingId = nil
            selectedMeetingIds.removeAll()
            return
        }
        // 旧プロジェクトの監視を停止
        if let oldProject = selectedProject {
            stopMeetingObservation(projectId: oldProject.id)
        }
        selectedProject = ProjectRecord(id: id, vaultId: vault.id, name: name, createdAt: .distantPast)
        selectedMeetingId = nil
        selectedMeetingIds.removeAll()
        startMeetingObservation(projectId: id)
    }

    /// transcript クリック時にプロジェクトを選択状態にする（selectedMeetingId を触らない）。
    func ensureProjectSelected(id: UUID, name: String) {
        guard let vault = currentVault else { return }
        guard selectedProject?.id != id else { return }
        if let oldProject = selectedProject {
            stopMeetingObservation(projectId: oldProject.id)
        }
        selectedProject = ProjectRecord(id: id, vaultId: vault.id, name: name, createdAt: .distantPast)
        startMeetingObservation(projectId: id)
    }

    func selectMeeting(_ id: UUID) {
        selectedMeetingId = id
    }

    // MARK: - Meeting Observation

    /// 指定プロジェクトのミーティング監視を開始する。
    func startMeetingObservation(projectId: UUID) {
        guard let dbQueue, meetingObservations[projectId] == nil else { return }

        let observation = ValueObservation.tracking { db in
            try MeetingRecord
                .filter(Column("projectId") == projectId)
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }

        meetingObservations[projectId] = observation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] meetings in
                Task { @MainActor in
                    guard let self else { return }
                    self.meetingsForProject[projectId] = meetings
                }
            }
        )
    }

    /// 指定プロジェクトのミーティング監視を停止する。
    func stopMeetingObservation(projectId: UUID) {
        meetingObservations[projectId]?.cancel()
        meetingObservations.removeValue(forKey: projectId)
        meetingsForProject.removeValue(forKey: projectId)
    }

    /// 選択プロジェクトに基づいてミーティング監視を同期する。
    private func refreshMeetingObservations() {
        let requiredIds: Set<UUID> = selectedProject.map { [$0.id] } ?? []

        // 不要な監視を停止
        for id in meetingObservations.keys where !requiredIds.contains(id) {
            stopMeetingObservation(projectId: id)
        }
        // 必要な監視を開始
        for id in requiredIds {
            startMeetingObservation(projectId: id)
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

        guard let repo = meetingRepository else { return }
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
        stopMeetingObservation(projectId: id)

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

        try? meetingRepository?.renameProjectsByPrefix(oldPrefix: name, newPrefix: newName, vaultId: vault.id)

        if isActive, let updated = try? meetingRepository?.fetchOrCreateProject(name: newName, vaultId: vault.id) {
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
            selectedMeetingId = nil
        }
        // 削除対象プロジェクトの meeting 監視を停止
        stopMeetingObservation(projectId: id)

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
            try meetingRepository?.deleteProjectsByPrefix(name: name, vaultId: vault.id)
        } catch {
            lastError = "データベースの更新に失敗しました: \(error.localizedDescription)"
            ErrorReportingService.capture(error, context: ["source": "deleteProject"])
        }
    }

    /// ディスクにフォルダを再作成し、missingOnDisk フラグをクリアする。
    func recreateFolder(name: String) {
        guard let vault = currentVault else { return }
        let url = projectURL(for: name)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try meetingRepository?.clearProjectsMissing(prefix: name, vaultId: vault.id)
        } catch {
            lastError = "フォルダの再作成に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Meeting Management

    func renameMeeting(id: UUID, newName: String) {
        try? meetingRepository?.renameMeeting(id: id, newName: newName)
    }

    func deleteMeeting(id: UUID) {
        try? meetingRepository?.deleteMeeting(id: id)
        selectedMeetingIds.remove(id)
        if selectedMeetingId == id {
            selectedMeetingId = nil
        }
    }

    /// 複数の文字起こしを一括削除する。
    func deleteMeetings(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        do {
            try meetingRepository?.deleteMeetings(ids: ids)
        } catch {
            lastError = error.localizedDescription
            return
        }
        if let selected = selectedMeetingId, ids.contains(selected) {
            selectedMeetingId = nil
        }
        selectedMeetingIds.subtract(ids)
    }

    func moveMeeting(id: UUID, toProjectId: UUID) {
        guard let repo = meetingRepository else { return }
        do {
            try repo.moveMeeting(id: id, toProjectId: toProjectId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 複数の文字起こしを一括移動する。
    func moveMeetings(ids: Set<UUID>, toProjectId: UUID) {
        guard let repo = meetingRepository, !ids.isEmpty else { return }
        do {
            try repo.moveMeetings(ids: ids, toProjectId: toProjectId)
        } catch {
            lastError = error.localizedDescription
            return
        }
        selectedMeetingIds.removeAll()
    }

    // MARK: - Multi-Selection Helpers

    /// Cmd+Click: トグル選択。
    func toggleMeetingSelection(_ id: UUID, projectId: UUID, projectName: String) {
        ensureProjectSelected(id: projectId, name: projectName)
        if selectedMeetingIds.contains(id) {
            selectedMeetingIds.remove(id)
            // 最後の選択解除なら selectedMeetingId もクリア
            if selectedMeetingIds.isEmpty {
                selectedMeetingId = nil
            } else {
                selectedMeetingId = selectedMeetingIds.first
            }
        } else {
            selectedMeetingIds.insert(id)
            // 最初の追加なら既存の単一選択も含める
            if let existing = selectedMeetingId, existing != id {
                selectedMeetingIds.insert(existing)
            }
            selectedMeetingId = id
        }
    }

    /// Shift+Click: 範囲選択。
    func rangeSelectMeeting(_ id: UUID, projectId: UUID, projectName: String) {
        ensureProjectSelected(id: projectId, name: projectName)
        let meetings = meetingsForProject[projectId] ?? []
        guard let anchor = selectedMeetingId,
              let anchorIndex = meetings.firstIndex(where: { $0.id == anchor }),
              let targetIndex = meetings.firstIndex(where: { $0.id == id }) else {
            // anchor がない場合は単一選択にフォールバック
            selectedMeetingIds = [id]
            selectedMeetingId = id
            return
        }
        let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
        selectedMeetingIds = Set(meetings[range].map(\.id))
        selectedMeetingId = id
    }

    /// 通常クリック: 単一選択（複数選択をクリア）。
    func singleSelectMeeting(_ id: UUID, projectId: UUID, projectName: String) {
        ensureProjectSelected(id: projectId, name: projectName)
        selectedMeetingIds = [id]
        selectedMeetingId = id
    }

    /// 選択中の文字起こし ID を返す（単一選択時も含む）。
    var effectiveSelectedIds: Set<UUID> {
        if selectedMeetingIds.isEmpty, let single = selectedMeetingId {
            return [single]
        }
        return selectedMeetingIds
    }
}
