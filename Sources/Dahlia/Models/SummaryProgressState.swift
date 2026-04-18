import Foundation

/// 要約生成の各ステップの進捗状態を管理する。
@MainActor @Observable
final class SummaryProgressState {
    enum StepStatus {
        case pending
        case running
        case completed
        case skipped
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .completed, .skipped, .failed: true
            default: false
            }
        }
    }

    var isVisible = false
    var vaultExport: StepStatus = .pending
    var summaryGeneration: StepStatus = .pending
    var driveExport: StepStatus?

    /// 全ステップが完了またはスキップ済みか。
    var isAllDone: Bool {
        vaultExport.isTerminal
            && summaryGeneration.isTerminal
            && (driveExport?.isTerminal ?? true)
    }

    func reset() {
        vaultExport = .pending
        summaryGeneration = .pending
        driveExport = nil
    }

    func show() {
        reset()
        isVisible = true
    }

    func dismiss() {
        isVisible = false
    }
}
