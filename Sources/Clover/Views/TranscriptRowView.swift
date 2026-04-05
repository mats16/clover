import SwiftUI

/// 議事録の1セグメントを表示する行ビュー。
struct TranscriptRowView: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // タイムスタンプ
            Text(Formatters.timeHHmmss.string(from: segment.startTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            // 話者ラベル
            if let speaker = segment.speakerLabel {
                Text(speakerDisplayName(for: speaker))
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(speakerColor(for: speaker))
                    .cornerRadius(4)
                    .frame(width: 56, alignment: .center)
            }

            // テキスト
            Text(segment.displayText)
                .font(.body)
                .foregroundColor(segment.isConfirmed ? .primary : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func speakerDisplayName(for label: String) -> String {
        switch label {
        case "mic": L10n.mic
        case "system": L10n.system
        default: label
        }
    }

    private func speakerColor(for label: String) -> Color {
        switch label {
        case "mic":
            return .blue
        case "system":
            return .orange
        default:
            let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
            let suffix = label.replacingOccurrences(of: "話者", with: "")
            let index: Int = switch suffix {
            case "A": 0
            case "B": 1
            case "C": 2
            case "D": 3
            case "E": 4
            case "F": 5
            case "G": 6
            case "H": 7
            default: (Int(suffix) ?? 1) - 1
            }
            return colors[index % colors.count]
        }
    }
}
