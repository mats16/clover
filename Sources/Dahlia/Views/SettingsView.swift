import SwiftUI

/// 設定画面のカテゴリ。
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case transcription
    case aiSummary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: L10n.general
        case .transcription: L10n.transcription
        case .aiSummary: L10n.aiSummary
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .transcription: "waveform"
        case .aiSummary: "sparkles"
        }
    }
}

/// 設定画面（Cmd+, で表示）。サイドバーでセクションを切り替える。
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab(SettingsCategory.general.label, systemImage: SettingsCategory.general.systemImage) {
                GeneralSettingsView()
            }
            Tab(SettingsCategory.transcription.label, systemImage: SettingsCategory.transcription.systemImage) {
                TranscriptionSettingsView()
            }
            Tab(SettingsCategory.aiSummary.label, systemImage: SettingsCategory.aiSummary.systemImage) {
                AISummarySettingsView()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
