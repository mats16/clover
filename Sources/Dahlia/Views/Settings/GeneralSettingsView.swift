import SwiftUI

/// 設定画面「一般」タブ。会議検出とエディタを管理する。
struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { settings.appLanguage },
                    set: { settings.appLanguage = $0 }
                )) {
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
                Toggle(isOn: Binding(
                    get: { settings.meetingDetectionEnabled },
                    set: { settings.meetingDetectionEnabled = $0 }
                )) {
                    Text(L10n.meetingDetection)
                    Text(L10n.meetingDetectionDescription)
                        .foregroundStyle(.secondary)
                }

                Picker(selection: Binding(
                    get: { settings.markdownEditor },
                    set: { settings.markdownEditor = $0 }
                )) {
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
