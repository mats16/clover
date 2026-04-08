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
    @State private var selection: SettingsCategory = .general

    var body: some View {
        HStack(spacing: 0) {
            // サイドバー
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                    .opacity(0.6)
                List(selection: $selection) {
                    ForEach(SettingsCategory.allCases) { category in
                        Label(category.label, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(width: 200)

            Divider()
                .ignoresSafeArea()

            // 詳細エリア
            Group {
                switch selection {
                case .general:
                    GeneralSettingsView()
                case .transcription:
                    TranscriptionSettingsView()
                case .aiSummary:
                    AISummarySettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 500)
        .background(WindowAccessor())
    }
}

/// Settings ウィンドウのタイトルバーを透明化してタイトルを非表示にする。
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
    }
}
