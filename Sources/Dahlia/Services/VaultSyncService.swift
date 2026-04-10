import CoreServices
import Foundation
import GRDB

/// 保管庫ディレクトリとの同期を管理する。
/// アプリ起動時の一括同期と FSEvents によるリアルタイム監視を提供する。
final class VaultSyncService: @unchecked Sendable {
    private let vaultURL: URL
    private let dbQueue: DatabaseQueue
    private let vaultId: UUID
    private var stream: FSEventStreamRef?
    private let fileManager = FileManager.default
    private let callbackQueue = DispatchQueue(label: "com.dahlia.vault-sync", qos: .utility)

    init(vaultURL: URL, dbQueue: DatabaseQueue, vaultId: UUID) {
        self.vaultURL = vaultURL
        self.dbQueue = dbQueue
        self.vaultId = vaultId
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Initial Sync

    /// vault 内の全ディレクトリをスキャンし、projects テーブルと同期する。
    func performInitialSync() {
        let diskNames = Set(scanAllDirectoryNames())
        try? dbQueue.write { db in
            try ProjectRecord.upsertAll(names: Array(diskNames), vaultId: self.vaultId, in: db)
            try self.reconcileMissingProjects(diskNames: diskNames, in: db)
        }
    }

    /// DB 内のプロジェクトとディスク上のフォルダを突合し、不整合を解消する。
    /// transcript を持たない孤立プロジェクトは削除、持つものは missingOnDisk フラグを設定する。
    private func reconcileMissingProjects(diskNames: Set<String>, in db: Database) throws {
        let allProjects = try ProjectRecord
            .filter(Column("vaultId") == self.vaultId)
            .fetchAll(db)

        // transcript を持つプロジェクト ID を一括取得（N+1 回避）
        let idsWithTranscripts = try UUID.fetchSet(db, sql: """
        SELECT DISTINCT projectId FROM transcripts
        WHERE projectId IN (SELECT id FROM projects WHERE vaultId = ?)
        """, arguments: [self.vaultId])

        for project in allProjects {
            let onDisk = diskNames.contains(project.name)
            let shouldBeMissing = !onDisk

            if shouldBeMissing {
                if idsWithTranscripts.contains(project.id) {
                    if !project.missingOnDisk {
                        var updated = project
                        updated.missingOnDisk = true
                        try updated.update(db)
                    }
                } else {
                    try project.delete(db)
                }
            } else if project.missingOnDisk {
                var updated = project
                updated.missingOnDisk = false
                try updated.update(db)
            }
        }
    }

    // MARK: - FSEvents Monitoring

    func startMonitoring() {
        guard stream == nil else { return }

        let pathsToWatch = [vaultURL.path as CFString] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes)

        guard let eventStream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(eventStream, callbackQueue)
        FSEventStreamStart(eventStream)
        stream = eventStream
    }

    func stopMonitoring() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - Directory Scanning

    func scanAllDirectoryNames() -> [String] {
        var names: [String] = []
        let vaultPath = vaultURL.path

        guard let enumerator = fileManager.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else { continue }

            let lastComponent = url.lastPathComponent
            if lastComponent.hasPrefix("_") || lastComponent.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }

            let fullPath = url.path
            guard fullPath.count > vaultPath.count + 1 else { continue }
            let relativePath = String(fullPath.dropFirst(vaultPath.count + 1))
            if !relativePath.isEmpty {
                names.append(relativePath)
            }
        }

        return names
    }

    // MARK: - DB Operations (direct, non-MainActor)

    private func upsertProjects(names: [String]) {
        guard !names.isEmpty else { return }
        try? dbQueue.write { db in
            try ProjectRecord.upsertAll(names: names, vaultId: self.vaultId, in: db)
            // 復活したフォルダの missingOnDisk を一括クリア
            try db.execute(
                sql: "UPDATE projects SET missingOnDisk = 0 WHERE vaultId = ? AND missingOnDisk = 1",
                arguments: [self.vaultId]
            )
        }
    }

    private func renameProjectsByPrefix(oldPrefix: String, newPrefix: String) {
        try? dbQueue.write { db in
            try ProjectRecord.renameByPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix, vaultId: self.vaultId, in: db)
        }
    }

    /// 削除されたフォルダ群を一括処理する。transcript ありなら missingOnDisk、なしなら DB 削除。
    private func handleDirectoryRemovals(_ relativePaths: [String], in db: Database) throws {
        guard !relativePaths.isEmpty else { return }

        // transcript を持つプロジェクト ID を一括取得（N+1 回避）
        let idsWithTranscripts = try UUID.fetchSet(db, sql: """
        SELECT DISTINCT projectId FROM transcripts
        WHERE projectId IN (SELECT id FROM projects WHERE vaultId = ?)
        """, arguments: [self.vaultId])

        let allProjects = try ProjectRecord
            .filter(Column("vaultId") == self.vaultId)
            .fetchAll(db)

        for relativePath in relativePaths {
            let matching = allProjects.filter {
                $0.name == relativePath || $0.name.hasPrefix(relativePath + "/")
            }
            let hasTranscripts = matching.contains { idsWithTranscripts.contains($0.id) }

            if hasTranscripts {
                try ProjectRecord.setMissingByPrefix(relativePath, missing: true, vaultId: self.vaultId, in: db)
            } else {
                try ProjectRecord.deleteByPrefix(relativePath, vaultId: self.vaultId, in: db)
            }
        }
    }

    // MARK: - FSEvents Handler

    func handleEvents(paths: [String], flags: [UInt32]) {
        let vaultPath = vaultURL.path + "/"

        var pendingRenames: [(path: String, exists: Bool)] = []
        var newDirs: [String] = []
        var removedDirs: [String] = []

        for (i, path) in paths.enumerated() {
            let flag = flags[i]
            let isDir = (flag & UInt32(kFSEventStreamEventFlagItemIsDir)) != 0
            guard isDir else { continue }

            guard path.hasPrefix(vaultPath) else { continue }
            let relativePath = String(path.dropFirst(vaultPath.count))
            guard !relativePath.isEmpty else { continue }

            let components = relativePath.split(separator: "/")
            let shouldSkip = components.contains { $0.hasPrefix(".") || $0.hasPrefix("_") }
            if shouldSkip { continue }

            let isRenamed = (flag & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
            let isCreated = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let isRemoved = (flag & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0

            if isRenamed {
                let exists = fileManager.fileExists(atPath: path)
                pendingRenames.append((path: relativePath, exists: exists))
            } else if isRemoved {
                if !fileManager.fileExists(atPath: path) {
                    removedDirs.append(relativePath)
                }
            } else if isCreated {
                if fileManager.fileExists(atPath: path) {
                    newDirs.append(relativePath)
                }
            }
        }

        // リネームペアの処理
        var i = 0
        while i < pendingRenames.count - 1 {
            let first = pendingRenames[i]
            let second = pendingRenames[i + 1]

            if !first.exists, second.exists {
                renameProjectsByPrefix(oldPrefix: first.path, newPrefix: second.path)
                i += 2
            } else if first.exists, !second.exists {
                renameProjectsByPrefix(oldPrefix: second.path, newPrefix: first.path)
                i += 2
            } else {
                if first.exists {
                    newDirs.append(first.path)
                } else {
                    removedDirs.append(first.path)
                }
                i += 1
            }
        }
        if i < pendingRenames.count {
            if pendingRenames[i].exists {
                newDirs.append(pendingRenames[i].path)
            } else {
                removedDirs.append(pendingRenames[i].path)
            }
        }

        if !removedDirs.isEmpty {
            try? dbQueue.write { db in
                try self.handleDirectoryRemovals(removedDirs, in: db)
            }
        }

        if !newDirs.isEmpty {
            var allNames: Set<String> = []
            for dir in newDirs {
                for path in ProjectRecord.allIntermediatePaths(for: dir) {
                    allNames.insert(path)
                }
            }
            upsertProjects(names: Array(allNames))
        }
    }
}

// MARK: - C Callback

private func fsEventsCallback(
    streamRef _: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds _: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let service = Unmanaged<VaultSyncService>.fromOpaque(info).takeUnretainedValue()

    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var paths: [String] = []
    var flags: [UInt32] = []

    for i in 0 ..< numEvents {
        if let cfPath = CFArrayGetValueAtIndex(cfPaths, i) {
            let path = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String
            paths.append(path)
            flags.append(eventFlags[i])
        }
    }

    service.handleEvents(paths: paths, flags: flags)
}
