import Combine
import Foundation
import GRDB

/// 文字起こし結果を GRDB/SQLite にリアルタイム保存するサービス。
/// 確定済みセグメントを差分で INSERT する。
@MainActor
final class TranscriptPersistenceService {
    private let store: TranscriptStore
    private let dbQueue: DatabaseQueue
    let transcriptionId: UUID
    private var cancellable: AnyCancellable?
    private var persistedSegmentIds: Set<UUID> = []

    /// 新規文字起こしを作成して録音を開始する。
    init(store: TranscriptStore, dbQueue: DatabaseQueue, projectId: UUID) {
        self.store = store
        self.dbQueue = dbQueue
        self.transcriptionId = .v7()

        let transcription = TranscriptionRecord(
            id: transcriptionId,
            projectId: projectId,
            title: "",
            startedAt: store.recordingStartTime ?? Date(),
            endedAt: nil,
            summaryCreated: false,
            filePath: nil
        )
        try? dbQueue.write { db in
            try transcription.insert(db)
        }

        startObserving()
    }

    /// 既存の文字起こしに追記する（追記モード）。
    init(store: TranscriptStore, dbQueue: DatabaseQueue, projectId _: UUID, existingTranscriptionId: UUID, existingSegmentIds: Set<UUID>) {
        self.store = store
        self.dbQueue = dbQueue
        self.transcriptionId = existingTranscriptionId
        self.persistedSegmentIds = existingSegmentIds

        // 文字起こしを再開（endedAt をクリア）
        try? dbQueue.write { db in
            if var record = try TranscriptionRecord.fetchOne(db, key: existingTranscriptionId) {
                record.endedAt = nil
                try record.update(db)
            }
        }

        startObserving()
    }

    private func startObserving() {
        cancellable = store.$segments
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] segments in
                self?.persistNewConfirmedSegments(segments)
            }
    }

    private func persistNewConfirmedSegments(_ segments: [TranscriptSegment]) {
        let newConfirmed = segments.filter {
            $0.isConfirmed && !persistedSegmentIds.contains($0.id)
        }
        guard !newConfirmed.isEmpty else { return }

        let records = newConfirmed.map { SegmentRecord(from: $0, transcriptionId: transcriptionId) }
        let newIds = Set(newConfirmed.map(\.id))
        persistedSegmentIds.formUnion(newIds)

        let queue = dbQueue
        Task.detached {
            try? queue.write { db in
                for record in records {
                    try record.insert(db)
                }
            }
        }
    }

    /// 監視を停止し、最終保存と文字起こし終了時刻の記録を行う。
    func stop() {
        cancellable = nil
        persistNewConfirmedSegments(store.segments)

        try? dbQueue.write { db in
            if var record = try TranscriptionRecord.fetchOne(db, key: transcriptionId) {
                record.endedAt = Date()
                try record.update(db)
            }
        }
    }

    /// 保存済みセグメント追跡をリセットし、監視を再開する。
    func reset() {
        persistedSegmentIds.removeAll()
        startObserving()
    }
}
