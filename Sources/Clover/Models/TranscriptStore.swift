import Foundation
import SwiftUI

/// 文字起こしセグメントの一元管理ストア。
/// @MainActor で SwiftUI と直接バインドする。
@MainActor
final class TranscriptStore: ObservableObject {
    @Published var segments: [TranscriptSegment] = []

    var recordingStartTime: Date?

    // MARK: - Unconfirmed Segment Throttle (per source)

    private var unconfirmedThrottleTasks: [String: Task<Void, Never>] = [:]
    private var pendingUnconfirmed: [String: [TranscriptSegment]] = [:]
    private var lastUnconfirmedUpdate: [String: ContinuousClock.Instant] = [:]
    private let throttleInterval: Duration = .milliseconds(200)

    func addSegment(_ segment: TranscriptSegment) {
        // 確定セグメントを startTime 順に挿入（複数ソース時の時系列順を保証）
        let insertIndex = segments.lastIndex(where: { $0.isConfirmed && $0.startTime <= segment.startTime })
            .map { segments.index(after: $0) }
            ?? segments.firstIndex(where: { !$0.isConfirmed })
            ?? segments.endIndex
        segments.insert(segment, at: insertIndex)
    }

    /// 指定ソースの未確定セグメントを置き換える。
    /// 他ソースの未確定セグメントには影響しない。
    /// 200ms 以内の連続呼び出しはスロットルし、最後の状態のみ反映する。
    func replaceUnconfirmedSegments(with newSegments: [TranscriptSegment], forSource sourceLabel: String? = nil) {
        let key = sourceLabel ?? ""
        let now = ContinuousClock.now
        pendingUnconfirmed[key] = newSegments

        let lastUpdate = lastUnconfirmedUpdate[key] ?? .now - throttleInterval
        guard now - lastUpdate >= throttleInterval else {
            if unconfirmedThrottleTasks[key] == nil {
                unconfirmedThrottleTasks[key] = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, let pending = self.pendingUnconfirmed[key] else { return }
                    self.applyUnconfirmedReplace(pending, forSource: sourceLabel)
                    self.unconfirmedThrottleTasks[key] = nil
                }
            }
            return
        }

        applyUnconfirmedReplace(newSegments, forSource: sourceLabel)
    }

    private func applyUnconfirmedReplace(_ newSegments: [TranscriptSegment], forSource sourceLabel: String? = nil) {
        segments.removeAll { !$0.isConfirmed && $0.speakerLabel == sourceLabel }
        segments.append(contentsOf: newSegments)
        let key = sourceLabel ?? ""
        lastUnconfirmedUpdate[key] = .now
        pendingUnconfirmed[key] = nil
    }

    /// DB から読み込んだセグメントを一括セットする。
    func loadSegments(_ newSegments: [TranscriptSegment]) {
        segments = newSegments
    }

    func clear() {
        segments.removeAll()
        recordingStartTime = nil
    }

    func exportAsText() -> String {
        segments.map { segment in
            let time = Formatters.timeHHmmss.string(from: segment.startTime)
            let speaker = segment.speakerLabel.map { "[\($0)] " } ?? ""
            return "[\(time)] \(speaker)\(segment.displayText)"
        }.joined(separator: "\n")
    }

    /// LLM 要約用のテキスト。スピーカーラベルを含めない。
    func exportForSummary() -> String {
        segments.map { segment in
            let time = Formatters.timeHHmmss.string(from: segment.startTime)
            return "[\(time)] \(segment.displayText)"
        }.joined(separator: "\n")
    }
}
