import Foundation

/// 要約生成の各ステップの進捗状態を管理する。
@MainActor @Observable
final class SummaryProgressState {
    enum StepStatus: Sendable {
        case pending
        case running
        case completed
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .completed, .failed: true
            default: false
            }
        }
    }

    var isVisible = false
    var screenshotExport: StepStatus?
    var transcriptExport: StepStatus = .pending
    var summaryGeneration: StepStatus = .pending

    /// 全ステップが完了またはスキップ済みか。
    var isAllDone: Bool {
        (screenshotExport?.isTerminal ?? true) && transcriptExport.isTerminal && summaryGeneration.isTerminal
    }

    func reset() {
        screenshotExport = nil
        transcriptExport = .pending
        summaryGeneration = .pending
    }

    func show() {
        reset()
        isVisible = true
    }

    func dismiss() {
        isVisible = false
    }
}
