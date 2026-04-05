import SwiftUI

/// 設定画面「一般」タブ。保管庫・エディタを管理する。
struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showVaultPicker = false

    var body: some View {
        Form {
            Section(L10n.vault) {
                HStack {
                    Text(settings.vaultPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(L10n.change) {
                        showVaultPicker = true
                    }
                }

                Text(L10n.vaultDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.editor) {
                Picker(L10n.markdownEditor, selection: Binding(
                    get: { settings.markdownEditor },
                    set: { settings.markdownEditor = $0 }
                )) {
                    ForEach(MarkdownEditor.availableEditors) { editor in
                        Text(editor.displayName).tag(editor)
                    }
                }

                Text(L10n.markdownEditorDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showVaultPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                settings.vaultPath = url.path
            }
        }
    }
}
