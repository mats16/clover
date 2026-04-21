import SwiftUI

/// 設定画面「Agent」タブ。Agent 起動コマンドを管理する。
struct AgentSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsPage {
            SettingsSection(
                title: L10n.agent,
                description: L10n.agentSettingsDescription
            ) {
                SettingsCard {
                    VStack(spacing: 0) {
                        SettingsControlRow(
                            title: L10n.agentLaunchCommand,
                            description: L10n.agentLaunchCommandDescription
                        ) {
                            TextField(AgentService.defaultLaunchCommand, text: $settings.agentLaunchCommand)
                                .textFieldStyle(.roundedBorder)
                        }

                        Divider()

                        SettingsControlRow(
                            title: L10n.agentPermissionMode,
                            description: L10n.agentPermissionModeDescription
                        ) {
                            Picker(L10n.agentPermissionMode, selection: $settings.agentPermissionMode) {
                                ForEach(AgentPermissionMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 220, alignment: .trailing)
                        }

                        Divider()

                        SettingsControlRow(
                            title: L10n.agentAllowedTools,
                            description: L10n.agentAllowedToolsDescription
                        ) {
                            AllowedToolsTokenField(text: $settings.agentAllowedTools)
                        }
                    }
                }
            }
        }
    }
}
