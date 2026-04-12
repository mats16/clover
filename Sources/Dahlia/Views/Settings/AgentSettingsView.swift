import SwiftUI

/// 設定画面「Agent」タブ。Agent 機能のオン/オフを管理する。
struct AgentSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.agentEnabled) {
                    Text(L10n.agentEnabled)
                    Text(L10n.agentEnabledDescription)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
