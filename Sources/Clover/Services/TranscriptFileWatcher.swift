import Foundation
import CoreServices
import GRDB

/// `_transcripts/` ディレクトリを FSEvents で監視し、
/// ファイル削除時に `transcripts.filePath` を nil に更新する。
final class TranscriptFileWatcher: Sendable {
    let dbQueue: DatabaseQueue
    private let vaultURL: URL
    private nonisolated(unsafe) var streamRef: FSEventStreamRef?
    private let callbackQueue = DispatchQueue(label: "com.clover.transcript-file-watcher", qos: .utility)

    init(dbQueue: DatabaseQueue, vaultURL: URL) {
        self.dbQueue = dbQueue
        self.vaultURL = vaultURL
    }

    func startMonitoring() {
        stopMonitoring()

        let vaultURL = self.vaultURL

        let transcriptsDir = TranscriptExportService.transcriptsDirectoryURL(in: vaultURL)
        try? FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)

        let pathsToWatch = [transcriptsDir.path as CFString] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            transcriptFileWatcherCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
    }

    func stopMonitoring() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    deinit {
        stopMonitoring()
    }

    /// DB 内の filePath が非 nil のレコードについてファイル存在を確認し、
    /// 存在しないものは filePath を nil に更新する。
    fileprivate func reconcileFilePaths() {
        do {
            // Read: ファイルパスと ID を取得（write ロック不要）
            let records = try dbQueue.read { db in
                try TranscriptionRecord
                    .filter(Column("filePath") != nil)
                    .fetchAll(db)
            }

            // ファイル存在チェック（DB ロック外）
            let missingIds = records.compactMap { record -> UUID? in
                guard let relativePath = record.filePath else { return nil }
                let absoluteURL = vaultURL.appendingPathComponent(relativePath)
                return FileManager.default.fileExists(atPath: absoluteURL.path) ? nil : record.id
            }

            // Write: 欠落分のみ更新
            guard !missingIds.isEmpty else { return }
            try dbQueue.write { db in
                for id in missingIds {
                    if var record = try TranscriptionRecord.fetchOne(db, key: id) {
                        record.filePath = nil
                        try record.update(db)
                    }
                }
            }
        } catch {
            print("[TranscriptFileWatcher] reconciliation error: \(error)")
        }
    }
}

// MARK: - FSEvents C コールバック

private func transcriptFileWatcherCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<TranscriptFileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    for i in 0..<numEvents {
        if eventFlags[i] & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            watcher.reconcileFilePaths()
            return
        }
    }
}
