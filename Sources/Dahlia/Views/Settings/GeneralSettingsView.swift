import SwiftUI

/// 設定画面「一般」タブ。会議検出とエディタを管理する。
struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    Text(L10n.appLanguage)
                    Text(L10n.appLanguageDescription)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(isOn: $settings.meetingDetectionEnabled) {
                    Text(L10n.meetingDetection)
                    Text(L10n.meetingDetectionDescription)
                        .foregroundStyle(.secondary)
                }

                Picker(selection: $settings.markdownEditor) {
                    ForEach(MarkdownEditor.availableEditors) { editor in
                        Text(editor.displayName).tag(editor)
                    }
                } label: {
                    Text(L10n.markdownEditor)
                    Text(L10n.markdownEditorDescription)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
