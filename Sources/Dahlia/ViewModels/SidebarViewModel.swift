import Foundation
import GRDB
import Observation
import SwiftUI

/// サイドバーの状態管理。DB 駆動の階層プロジェクトツリーと文字起こし一覧を管理する。
@Observable
@MainActor
final class SidebarViewModel {

    // MARK: - Observed State

    var selectedDestination: SidebarDestination = .home
    var flatProjects: [FlatProjectRow] = []
    var selectedProject: ProjectRecord?
    var selectedMeetingSelection: MeetingScreenSelection?
    /// 複数選択中の文字起こし ID。
    var selectedMeetingIds: Set<UUID> = []
    /// 複数選択の範囲指定に使うアンカー。
    @ObservationIgnored private var selectionAnchorMeetingId: UUID?
    /// 現在の vault に属する全 meeting の一覧。
    var allMeetings: [MeetingOverviewItem] = []
    /// 現在の vault に属する全 project の集約一覧。
    var allProjectItems: [ProjectOverviewItem] = []
    /// 現在の vault に属する全 action item の集約一覧。
    var allActionItems: [ActionItemOverviewItem] = []
    /// 現在の vault に属する全 instructions の一覧。
    var allInstructions: [InstructionRecord] = []
    /// 複数選択中のプロジェクト ID。
    var selectedProjectIds: Set<UUID> = []
    /// プロジェクト複数選択の範囲指定に使うアンカー。
    @ObservationIgnored private var selectionAnchorProjectId: UUID?
    /// 展開中のプロジェクトごとの文字起こし一覧（プロジェクトID → レコード配列）。
    var meetingsForProject: [UUID: [MeetingRecord]] = [:]
    var lastError: String?
    var allVaults: [VaultRecord] = []
    var allTags: [TagRecord] = []
    var selectedInstruction: InstructionRecord?

    /// 後方互換: 選択中プロジェクトの文字起こし一覧。
    var meetingsForSelectedProject: [MeetingRecord] {
        guard let project = selectedProject else { return [] }
        return meetingsForProject[project.id] ?? []
    }

    var selectedMeetingId: UUID? {
        selectedMeetingSelection?.meetingId
    }

    var selectedDraftMeetingId: UUID? {
        selectedMeetingSelection?.draftId
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

    /// Projects タブでプロジェクトが選択されている場合のコンテキスト。未選択なら全て nil。
    var selectedProjectContext: (projectURL: URL?, projectId: UUID?, projectName: String?) {
        guard selectedDestination == .projects,
              let project = selectedProject,
              let url = selectedProjectURL else {
            return (nil, nil, nil)
        }
        return (url, project.id, project.name)
    }

    @ObservationIgnored private var meetingRepository: MeetingRepository?
    @ObservationIgnored private var fileWatcher: TranscriptFileWatcher?
    @ObservationIgnored private var meetingObservations: [UUID: AnyDatabaseCancellable] = [:]
    @ObservationIgnored private var allMeetingsObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var allTagsObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var allProjectsObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var allActionItemsObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var instructionsObservation: AnyDatabaseCancellable?
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
        allMeetingsObservation?.cancel()
        allTagsObservation?.cancel()
        allProjectsObservation?.cancel()
        allActionItemsObservation?.cancel()
        instructionsObservation?.cancel()
        fileWatcher?.stopMonitoring()

        // 全 meeting 監視を停止
        for (_, cancellable) in meetingObservations {
            cancellable.cancel()
        }
        meetingObservations.removeAll()
        meetingsForProject.removeAll()
        allMeetings.removeAll()
        allTags.removeAll()
        allProjectItems.removeAll()
        allActionItems.removeAll()
        allInstructions.removeAll()

        // 選択状態をリセット
        selectedProject = nil
        selectedInstruction = nil
        clearMeetingSelection()
        clearProjectSelection()

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
            AppSettings.shared.selectedInstructionID = nil
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

        // TranscriptFileWatcher: _dahlia/transcripts/ ディレクトリの監視
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
                    if let selectedProject = self.selectedProject,
                       let refreshedProject = records.first(where: { $0.id == selectedProject.id }) {
                        self.selectedProject = refreshedProject
                    }
                    guard self.flatProjects != rows else { return }
                    self.flatProjects = rows
                    self.syncCollapseState()
                }
            }
        )

        let meetingsObservation = ValueObservation.tracking { db in
            try MeetingOverviewItem.fetchAll(
                db,
                sql: """
                SELECT
                    meetings.id AS meetingId,
                    meetings.vaultId AS vaultId,
                    meetings.projectId AS projectId,
                    projects.name AS projectName,
                    meetings.name AS meetingName,
                    meetings.status AS status,
                    meetings.duration AS duration,
                    meetings.createdAt AS createdAt,
                    EXISTS(SELECT 1 FROM summaries WHERE summaries.meetingId = meetings.id) AS hasSummary,
                    COUNT(segments.id) AS segmentCount,
                    (
                        SELECT preview.text
                        FROM transcript_segments AS preview
                        WHERE preview.meetingId = meetings.id
                        ORDER BY preview.startTime DESC
                        LIMIT 1
                    ) AS latestSegmentText,
                    (SELECT GROUP_CONCAT(t.name || char(30) || t.colorHex, char(31))
                     FROM meeting_tags mt
                     INNER JOIN tags t ON t.id = mt.tagId
                     WHERE mt.meetingId = meetings.id) AS tags
                FROM meetings
                LEFT JOIN projects ON projects.id = meetings.projectId
                LEFT JOIN transcript_segments AS segments ON segments.meetingId = meetings.id
                WHERE meetings.vaultId = ?
                GROUP BY meetings.id
                ORDER BY meetings.createdAt DESC, meetings.id DESC
                """,
                arguments: [vaultId]
            )
        }
        allMeetingsObservation = meetingsObservation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] meetings in
                Task { @MainActor in
                    guard let self else { return }
                    self.allMeetings = meetings
                }
            }
        )

        // tags テーブルの ValueObservation でタグマスタを自動更新
        let tagsObservation = ValueObservation.tracking { db in
            try TagRecord.order(Column("name").asc).fetchAll(db)
        }
        allTagsObservation = tagsObservation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] tags in
                Task { @MainActor in
                    guard let self else { return }
                    self.allTags = tags
                    self.allAvailableTags = tags.map { TagInfo(name: $0.name, colorHex: $0.colorHex) }
                }
            }
        )

        let projectsOverviewObservation = ValueObservation.tracking { db in
            let projects = try ProjectOverviewItem.fetchAll(
                db,
                sql: """
                SELECT
                    projects.id AS projectId,
                    projects.name AS projectName,
                    projects.createdAt AS createdAt,
                    projects.googleDriveFolderId AS googleDriveFolderId,
                    projects.missingOnDisk AS missingOnDisk,
                    COUNT(meetings.id) AS meetingCount,
                    MAX(meetings.createdAt) AS latestMeetingDate
                FROM projects
                LEFT JOIN meetings ON meetings.projectId = projects.id
                WHERE projects.vaultId = ?
                GROUP BY projects.id
                """,
                arguments: [vaultId]
            )
            return projects.sorted { lhs, rhs in
                let comparison = lhs.projectName.localizedStandardCompare(rhs.projectName)
                if comparison == .orderedSame {
                    return lhs.projectId.uuidString < rhs.projectId.uuidString
                }
                return comparison == .orderedAscending
            }
        }
        allProjectsObservation = projectsOverviewObservation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] projects in
                Task { @MainActor in
                    guard let self else { return }
                    self.allProjectItems = projects
                }
            }
        )

        let actionItemsObservation = ValueObservation.tracking { db in
            let actionItems = try ActionItemOverviewItem.fetchAll(
                db,
                sql: """
                SELECT
                    action_items.id AS actionItemId,
                    action_items.meetingId AS meetingId,
                    meetings.projectId AS projectId,
                    projects.name AS projectName,
                    meetings.name AS meetingName,
                    meetings.createdAt AS meetingCreatedAt,
                    action_items.title AS title,
                    action_items.assignee AS assignee,
                    action_items.isCompleted AS isCompleted
                FROM action_items
                INNER JOIN meetings ON meetings.id = action_items.meetingId
                LEFT JOIN projects ON projects.id = meetings.projectId
                WHERE meetings.vaultId = ?
                """,
                arguments: [vaultId]
            )

            return actionItems.sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted && rhs.isCompleted
                }
                if lhs.sortsAsMine != rhs.sortsAsMine {
                    return lhs.sortsAsMine && !rhs.sortsAsMine
                }
                if lhs.meetingCreatedAt != rhs.meetingCreatedAt {
                    return lhs.meetingCreatedAt > rhs.meetingCreatedAt
                }

                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }

                let assigneeComparison = lhs.assignee.localizedCaseInsensitiveCompare(rhs.assignee)
                if assigneeComparison != .orderedSame {
                    return assigneeComparison == .orderedAscending
                }

                return lhs.actionItemId.uuidString < rhs.actionItemId.uuidString
            }
        }
        allActionItemsObservation = actionItemsObservation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] actionItems in
                Task { @MainActor in
                    guard let self else { return }
                    self.allActionItems = actionItems
                }
            }
        )

        let instructionsValueObservation = ValueObservation.tracking { db in
            try InstructionRecord
                .filter(Column("vaultId") == vaultId)
                .order(Column("name").asc)
                .fetchAll(db)
        }
        instructionsObservation = instructionsValueObservation.start(
            in: dbQueue,
            onError: { _ in },
            onChange: { [weak self] instructions in
                Task { @MainActor in
                    guard let self else { return }
                    self.allInstructions = instructions

                    if let selectedInstruction = self.selectedInstruction {
                        let updated = instructions.first(where: { $0.id == selectedInstruction.id })
                        if updated != selectedInstruction {
                            self.selectedInstruction = updated
                        }
                    }

                    if let selectedInstructionID = AppSettings.shared.selectedInstructionID,
                       !instructions.contains(where: { $0.id == selectedInstructionID }) {
                        AppSettings.shared.selectedInstructionID = nil
                    }
                }
            }
        )
    }

    // MARK: - Selection

    /// プロジェクト選択を解除し、関連するミーティング選択もクリアする。
    func deselectProject() {
        if let oldProject = selectedProject {
            stopMeetingObservation(projectId: oldProject.id)
        }
        selectedProject = nil
        clearMeetingSelection()
    }

    /// プロジェクト選択だけを解除し、表示中のミーティング選択は維持する。
    func deselectProjectKeepingMeetingSelection() {
        if let oldProject = selectedProject {
            stopMeetingObservation(projectId: oldProject.id)
        }
        selectedProject = nil
    }

    func selectProject(id: UUID, name: String) {
        guard let vault = currentVault else { return }
        if selectedProject?.id == id {
            clearMeetingSelection()
            return
        }
        // 旧プロジェクトの監視を停止
        if let oldProject = selectedProject {
            stopMeetingObservation(projectId: oldProject.id)
        }
        selectedProject = ProjectRecord(
            id: id,
            vaultId: vault.id,
            name: name,
            createdAt: .distantPast,
            googleDriveFolderId: allProjectItems.first(where: { $0.projectId == id })?.googleDriveFolderId
        )
        clearMeetingSelection()
        startMeetingObservation(projectId: id)
    }

    /// transcript クリック時にプロジェクトを選択状態にする（selectedMeetingId を触らない）。
    func ensureProjectSelected(id: UUID, name: String) {
        guard let vault = currentVault else { return }
        guard selectedProject?.id != id else { return }
        if let oldProject = selectedProject {
            stopMeetingObservation(projectId: oldProject.id)
        }
        selectedProject = ProjectRecord(
            id: id,
            vaultId: vault.id,
            name: name,
            createdAt: .distantPast,
            googleDriveFolderId: allProjectItems.first(where: { $0.projectId == id })?.googleDriveFolderId
        )
        startMeetingObservation(projectId: id)
    }

    func selectMeeting(_ id: UUID) {
        selectedMeetingSelection = .persisted(id)
        selectionAnchorMeetingId = id
    }

    func selectDraftMeeting(_ id: UUID) {
        selectedMeetingSelection = .draft(id)
        selectionAnchorMeetingId = nil
    }

    func selectInstruction(_ id: UUID?) {
        guard let id else {
            selectedInstruction = nil
            return
        }
        selectedInstruction = allInstructions.first(where: { $0.id == id })
    }

    func selectDestination(_ destination: SidebarDestination) {
        if selectedDestination == destination {
            if destination == .meetings {
                clearMeetingSelection()
            } else if destination == .projects {
                clearProjectSelection()
                deselectProject()
            } else if destination == .actionItems {
                clearProjectSelection()
                deselectProject()
                clearMeetingSelection()
            } else if destination == .instructions {
                selectedInstruction = nil
            }
            return
        }

        selectedDestination = destination
    }

    /// ミーティング選択状態をクリアする（no-op ガード付き）。
    func clearMeetingSelection() {
        if selectedMeetingSelection != nil {
            selectedMeetingSelection = nil
        }
        if !selectedMeetingIds.isEmpty {
            selectedMeetingIds.removeAll()
        }
        selectionAnchorMeetingId = nil
    }

    func useInstructionForSummary(_ instructionID: UUID?) {
        AppSettings.shared.selectedInstructionID = instructionID
    }

    func createInstruction() -> InstructionRecord? {
        guard let vault = currentVault,
              let meetingRepository else { return nil }

        do {
            let instruction = try meetingRepository.createInstruction(
                vaultId: vault.id,
                name: nextInstructionName(),
                content: AppSettings.defaultSummaryPrompt
            )
            selectedInstruction = instruction
            return instruction
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func updateInstruction(id: UUID, name: String, content: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            try meetingRepository?.updateInstruction(id: id, name: trimmedName, content: content)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteInstruction(id: UUID) {
        do {
            try meetingRepository?.deleteInstruction(id: id)
            if selectedInstruction?.id == id {
                selectedInstruction = nil
            }
            if AppSettings.shared.selectedInstructionID == id {
                AppSettings.shared.selectedInstructionID = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func nextInstructionName() -> String {
        let existingNames = Set(allInstructions.map(\.name))
        var name = "new_instruction"
        var counter = 1

        while existingNames.contains(name) {
            name = "new_instruction_\(counter)"
            counter += 1
        }

        return name
    }

    // MARK: - Meeting Observation

    /// 指定プロジェクトのミーティング監視を開始する。
    func startMeetingObservation(projectId: UUID) {
        guard let dbQueue, meetingObservations[projectId] == nil else { return }

        let observation = ValueObservation.tracking { db in
            try MeetingRecord
                .filter(Column("projectId") == projectId)
                .order(Column("createdAt").desc)
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
        // "/" を含む名前は禁止（フラットプロジェクト）
        guard !name.contains("/") else {
            lastError = "プロジェクト名に「/」は使用できません。"
            return
        }
        guard let vault = currentVault else { return }
        let projectURL = projectURL(for: name)
        do {
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let repo = meetingRepository else { return }
        if let record = try? repo.fetchOrCreateProject(name: name, vaultId: vault.id) {
            selectProject(id: record.id, name: record.name)
        }
    }

    /// プロジェクトを取得または作成し、対応するフォルダ URL を返す。
    func fetchOrCreateProject(name: String) -> (record: ProjectRecord, url: URL)? {
        guard let vault = currentVault,
              let repository = meetingRepository else { return nil }

        let projectURL = vault.url.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: projectURL,
                withIntermediateDirectories: true
            )
            let record = try repository.fetchOrCreateProject(name: name, vaultId: vault.id)
            return (record, projectURL)
        } catch {
            lastError = error.localizedDescription
            return nil
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

    func deleteProject(id: UUID, name: String) {
        guard let vault = currentVault else { return }
        let projectURL = projectURL(for: name)

        if let selected = selectedProject,
           selected.id == id || selected.name.hasPrefix(name + "/") {
            selectedProject = nil
            selectedMeetingSelection = nil
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

    func updateProjectGoogleDriveFolder(id: UUID, folderId: String?) {
        do {
            try meetingRepository?.updateProjectGoogleDriveFolder(id: id, folderId: folderId)
            if selectedProject?.id == id {
                let trimmedFolderID = folderId?.trimmingCharacters(in: .whitespacesAndNewlines)
                selectedProject?.googleDriveFolderId = if let trimmedFolderID, !trimmedFolderID.isEmpty {
                    trimmedFolderID
                } else {
                    nil
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Meeting Management

    func renameMeeting(id: UUID, newName: String) {
        try? meetingRepository?.renameMeeting(id: id, newName: newName)
    }

    private static let tagColorPalette = [
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
        "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
        "#BB8FCE", "#85C1E9",
    ]

    func addTagToMeeting(id: UUID, tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let colorHex = Self.tagColorPalette.randomElement() ?? "#808080"
        try? meetingRepository?.addTag(name: trimmed, toMeetingId: id, colorHex: colorHex)
    }

    func removeTagFromMeeting(id: UUID, tag: String) {
        try? meetingRepository?.removeTag(name: tag, fromMeetingId: id)
    }

    func setActionItemCompleted(id: UUID, isCompleted: Bool) {
        do {
            try meetingRepository?.setActionItemCompleted(id: id, isCompleted: isCompleted)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setActionItemAssignee(id: UUID, assignee: String) {
        do {
            try meetingRepository?.setActionItemAssignee(id: id, assignee: assignee)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteActionItem(id: UUID) {
        do {
            try meetingRepository?.deleteActionItem(id: id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private(set) var allAvailableTags: [TagInfo] = []

    func deleteMeeting(id: UUID) {
        try? meetingRepository?.deleteMeeting(id: id)
        selectedMeetingIds.remove(id)
        if selectedMeetingId == id {
            selectedMeetingSelection = nil
        }
        if selectionAnchorMeetingId == id {
            selectionAnchorMeetingId = selectedMeetingIds.first
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
            selectedMeetingSelection = nil
        }
        selectedMeetingIds.subtract(ids)
        if let anchor = selectionAnchorMeetingId, ids.contains(anchor) {
            selectionAnchorMeetingId = selectedMeetingIds.first
        }
    }

    func moveMeeting(id: UUID, toProjectId: UUID?) {
        guard let repo = meetingRepository else { return }
        do {
            try repo.moveMeeting(id: id, toProjectId: toProjectId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 複数の文字起こしを一括移動する。
    func moveMeetings(ids: Set<UUID>, toProjectId: UUID?) {
        guard let repo = meetingRepository, !ids.isEmpty else { return }
        do {
            try repo.moveMeetings(ids: ids, toProjectId: toProjectId)
        } catch {
            lastError = error.localizedDescription
            return
        }
        if let selected = selectedMeetingId, ids.contains(selected) {
            selectedMeetingSelection = nil
        }
        selectedMeetingIds.removeAll()
        selectionAnchorMeetingId = nil
    }

    // MARK: - Multi-Selection Helpers

    private func selectionScopeMeetings(for projectId: UUID?) -> [MeetingRecord] {
        guard let projectId, selectedDestination != .meetings else {
            return allMeetings.map(\.meeting)
        }
        return meetingsForProject[projectId] ?? []
    }

    private func applyProjectContext(projectId: UUID?, projectName: String?) {
        if let projectId, let projectName {
            ensureProjectSelected(id: projectId, name: projectName)
        } else {
            deselectProjectKeepingMeetingSelection()
        }
    }

    /// Cmd+Click: トグル選択。
    func toggleMeetingSelection(_ id: UUID, projectId: UUID?, projectName: String?) {
        applyProjectContext(projectId: projectId, projectName: projectName)

        if selectedMeetingIds.isEmpty, let existing = selectedMeetingId {
            selectedMeetingIds = [existing]
            selectionAnchorMeetingId = existing
        }
        selectedMeetingSelection = nil

        if selectedMeetingIds.contains(id) {
            selectedMeetingIds.remove(id)
            if selectedMeetingIds.isEmpty {
                selectionAnchorMeetingId = nil
            } else if selectionAnchorMeetingId == id {
                selectionAnchorMeetingId = selectedMeetingIds.first
            }
        } else {
            selectedMeetingIds.insert(id)
            selectionAnchorMeetingId = id
        }
    }

    /// Shift+Click: 範囲選択。
    func rangeSelectMeeting(_ id: UUID, projectId: UUID?, projectName: String?) {
        applyProjectContext(projectId: projectId, projectName: projectName)
        let meetings = selectionScopeMeetings(for: projectId)
        let anchorId = selectionAnchorMeetingId ?? selectedMeetingId
        selectedMeetingSelection = nil

        guard let anchor = anchorId,
              let anchorIndex = meetings.firstIndex(where: { $0.id == anchor }),
              let targetIndex = meetings.firstIndex(where: { $0.id == id }) else {
            selectedMeetingIds = [id]
            selectionAnchorMeetingId = id
            return
        }
        let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
        selectedMeetingIds = Set(meetings[range].map(\.id))
        selectionAnchorMeetingId = id
    }

    /// 通常クリック: 単一選択（複数選択をクリア）。
    func singleSelectMeeting(_ id: UUID, projectId: UUID?, projectName: String?) {
        applyProjectContext(projectId: projectId, projectName: projectName)
        selectedMeetingIds = [id]
        selectedMeetingSelection = .persisted(id)
        selectionAnchorMeetingId = id
    }

    /// 選択中の文字起こし ID を返す（単一選択時も含む）。
    var effectiveSelectedIds: Set<UUID> {
        if selectedMeetingIds.isEmpty, let single = selectedMeetingId {
            return [single]
        }
        return selectedMeetingIds
    }

    // MARK: - Project Multi-Selection

    /// 選択中のプロジェクト ID を返す（単一選択時も含む）。
    var effectiveSelectedProjectIds: Set<UUID> {
        if selectedProjectIds.isEmpty, let single = selectedProject {
            return [single.id]
        }
        return selectedProjectIds
    }

    /// Cmd+Click: プロジェクトのトグル選択。
    func toggleProjectSelection(_ id: UUID) {
        if selectedProjectIds.isEmpty, let existing = selectedProject {
            selectedProjectIds = [existing.id]
            selectionAnchorProjectId = existing.id
        }
        selectedProject = nil

        if selectedProjectIds.contains(id) {
            selectedProjectIds.remove(id)
            if selectedProjectIds.isEmpty {
                selectionAnchorProjectId = nil
            } else if selectionAnchorProjectId == id {
                selectionAnchorProjectId = selectedProjectIds.first
            }
        } else {
            selectedProjectIds.insert(id)
            selectionAnchorProjectId = id
        }
    }

    /// Shift+Click: プロジェクトの範囲選択。
    func rangeSelectProject(_ id: UUID) {
        let projects = allProjectItems
        let anchorId = selectionAnchorProjectId ?? selectedProject?.id
        selectedProject = nil

        guard let anchor = anchorId,
              let anchorIndex = projects.firstIndex(where: { $0.projectId == anchor }),
              let targetIndex = projects.firstIndex(where: { $0.projectId == id }) else {
            selectedProjectIds = [id]
            selectionAnchorProjectId = id
            return
        }
        let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
        selectedProjectIds = Set(projects[range].map(\.projectId))
        selectionAnchorProjectId = id
    }

    /// 通常クリック: プロジェクトの単一選択（Projects Overview からのナビゲーション用）。
    func singleSelectProjectFromOverview(_ id: UUID, name: String) {
        selectedProjectIds.removeAll()
        selectionAnchorProjectId = id
        selectProject(id: id, name: name)
    }

    /// プロジェクトの複数選択をクリアする。
    func clearProjectSelection() {
        if !selectedProjectIds.isEmpty {
            selectedProjectIds.removeAll()
        }
        selectionAnchorProjectId = nil
    }

    /// 複数のプロジェクトを一括削除する。
    func deleteProjects(ids: Set<UUID>) {
        guard let vault = currentVault, !ids.isEmpty else { return }
        for id in ids {
            guard let item = allProjectItems.first(where: { $0.projectId == id }) else { continue }
            let url = projectURL(for: item.projectName)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            try? meetingRepository?.deleteProjectsByPrefix(name: item.projectName, vaultId: vault.id)
        }
        if let selected = selectedProject, ids.contains(selected.id) {
            selectedProject = nil
            selectedMeetingSelection = nil
        }
        selectedProjectIds.subtract(ids)
        if let anchor = selectionAnchorProjectId, ids.contains(anchor) {
            selectionAnchorProjectId = selectedProjectIds.first
        }
    }
}
