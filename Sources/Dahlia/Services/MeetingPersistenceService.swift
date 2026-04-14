import Combine
import Foundation
import GRDB

/// ミーティングの文字起こし結果を GRDB/SQLite にリアルタイム保存するサービス。
/// 確定済みセグメントを差分で INSERT する。
@MainActor
final class MeetingPersistenceService {
    private let store: TranscriptStore
    private let dbQueue: DatabaseQueue
    let meetingId: UUID
    private var cancellable: AnyCancellable?
    private var persistedSegmentIds: Set<UUID> = []

    /// 新規ミーティングを作成して録音を開始する。
    init(store: TranscriptStore, dbQueue: DatabaseQueue, projectId: UUID) {
        self.store = store
        self.dbQueue = dbQueue
        self.meetingId = .v7()

        let meeting = MeetingRecord(
            id: meetingId,
            projectId: projectId,
            name: "",
            startedAt: store.recordingStartTime ?? Date(),
            endedAt: nil
        )
        try? dbQueue.write { db in
            try meeting.insert(db)
        }

        startObserving()
    }

    /// 既存のミーティングに追記する（追記モード）。
    init(store: TranscriptStore, dbQueue: DatabaseQueue, projectId _: UUID, existingMeetingId: UUID, existingSegmentIds: Set<UUID>) {
        self.store = store
        self.dbQueue = dbQueue
        self.meetingId = existingMeetingId
        self.persistedSegmentIds = existingSegmentIds

        // ミーティングを再開（endedAt をクリア）
        try? dbQueue.write { db in
            if var record = try MeetingRecord.fetchOne(db, key: existingMeetingId) {
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

        let records = newConfirmed.map { TranscriptSegmentRecord(from: $0, meetingId: meetingId) }
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

    /// 監視を停止し、最終保存とミーティング終了時刻の記録を行う。
    func stop() {
        cancellable = nil
        persistNewConfirmedSegments(store.segments)

        try? dbQueue.write { db in
            if var record = try MeetingRecord.fetchOne(db, key: meetingId) {
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
