import SwiftUI

/// 要約生成時に右下に表示する進捗トースト。
struct SummaryProgressToastView: View {
    let state: SummaryProgressState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("要約を生成中")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            StepRow(label: "要約の生成", status: state.summaryGeneration)
            StepRow(label: "Vault へ書き出し", status: state.vaultExport)
            if let driveStatus = state.driveExport {
                StepRow(label: "Google Drive へ書き出し", status: driveStatus)
            }
        }
        .padding(12)
        .frame(width: 220)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct StepRow: View {
    let label: String
    let status: SummaryProgressState.StepStatus

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(textColor)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    private var textColor: Color {
        switch status {
        case .pending: .secondary
        case .running: .primary
        case .completed, .skipped: .secondary
        case .failed: .red
        }
    }
}
