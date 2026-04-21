import SwiftUI

/// 設定画面「通知」タブ。ミーティング検出ポップアップを管理する。
struct NotificationSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsPage {
            SettingsSection(
                title: L10n.notifications,
                description: L10n.notificationSettingsDescription
            ) {
                SettingsCard {
                    SettingsToggleRow(
                        title: L10n.meetingDetection,
                        description: L10n.meetingDetectionDescription,
                        isOn: $settings.meetingDetectionEnabled
                    )
                }
            }
        }
    }
}
