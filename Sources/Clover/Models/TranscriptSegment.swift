import Foundation

enum Formatters {
    static let timeHHmmss: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

}

extension Sequence where Element == Locale {
    func sortedByLocalizedName() -> [Locale] {
        sorted {
            ($0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
                < ($1.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
        }
    }
}

/// Speech フレームワークで文字起こしされた1発話区間を表すデータモデル。
struct TranscriptSegment: Identifiable, Equatable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var text: String
    var isConfirmed: Bool
    var speakerLabel: String?

    /// 表示用テキスト。
    var displayText: String { text }

    /// セグメントの長さ（秒）。endTime が未設定なら nil。
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    init(
        id: UUID = .v7(),
        startTime: Date,
        endTime: Date? = nil,
        text: String,
        isConfirmed: Bool = false,
        speakerLabel: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.isConfirmed = isConfirmed
        self.speakerLabel = speakerLabel
    }

    /// SegmentRecord からの変換イニシャライザ。
    init(from record: SegmentRecord) {
        self.id = record.id
        self.startTime = record.startTime
        self.endTime = record.endTime
        self.text = record.text
        self.isConfirmed = record.isConfirmed
        self.speakerLabel = record.speakerLabel
    }
}
