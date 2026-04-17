import SwiftUI

/// 設定画面のカテゴリ。
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case calendar
    case transcription
    case aiSummary
    case agent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: L10n.general
        case .calendar: L10n.calendar
        case .transcription: L10n.transcription
        case .aiSummary: L10n.aiSummary
        case .agent: L10n.agent
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .calendar: "calendar"
        case .transcription: "waveform"
        case .aiSummary: "sparkles"
        case .agent: "cpu"
        }
    }
}

/// 設定画面（Cmd+, で表示）。サイドバーでセクションを切り替える。
struct SettingsView: View {
    @State private var selection: SettingsCategory? = .general
    private let sidebarWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(SettingsCategory.allCases) { category in
                        settingsSidebarRow(for: category)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)

                Spacer(minLength: 0)
            }
            .frame(width: sidebarWidth)
            .background(.bar)

            Divider()

            selectedCategoryView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    private var selectedCategoryView: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsView()
        case .calendar:
            CalendarSettingsView()
        case .transcription:
            TranscriptionSettingsView()
        case .aiSummary:
            AISummarySettingsView()
        case .agent:
            AgentSettingsView()
        }
    }

    private func settingsSidebarRow(for category: SettingsCategory) -> some View {
        Button {
            selection = category
        } label: {
            Label(category.label, systemImage: category.systemImage)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selection == category ? Color.primary.opacity(0.08) : Color.clear)
        )
    }
}
