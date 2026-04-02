import SwiftUI
import Speech
import UniformTypeIdentifiers

/// 設定画面（Cmd+, で表示）。
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var supportedLocales: [Locale] = []
    @State private var isLoadingLocales = false
    @State private var showVaultPicker = false
    @State private var localeSearchText = ""

    var body: some View {
        Form {
            Section("保管庫") {
                HStack {
                    Text(settings.vaultPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("変更...") {
                        showVaultPicker = true
                    }
                }

                Text("プロジェクトフォルダが格納されるルートディレクトリです。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                if isLoadingLocales {
                    ProgressView("対応言語を読み込み中...")
                        .font(.caption)
                } else {
                    TextField("言語を検索...", text: $localeSearchText)
                        .textFieldStyle(.roundedBorder)

                    let searchedLocales = searchFilteredLocales
                    if searchedLocales.isEmpty {
                        Text("該当する言語がありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(searchedLocales, id: \.identifier) { locale in
                                    let id = locale.identifier
                                    let isEnabled = settings.isLocaleEnabled(id)
                                    Button {
                                        toggleLocale(id)
                                    } label: {
                                        HStack {
                                            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isEnabled ? .accentColor : .secondary)
                                            Text(locale.localizedString(forIdentifier: id) ?? id)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text(id)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 200)
                    }

                    HStack {
                        let enabledCount = settings.enabledLocaleIdentifiers.count
                        Text(enabledCount == 0
                             ? "すべての言語を表示中"
                             : "\(enabledCount) 言語を選択中")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !settings.enabledLocaleIdentifiers.isEmpty {
                            Button("すべて表示に戻す") {
                                settings.enabledLocaleIdentifiers = []
                            }
                            .font(.caption)
                        }
                    }
                }
            } header: {
                Text("表示する言語")
            } footer: {
                Text("選択した言語のみが言語ピッカーに表示されます。未選択の場合はすべての言語が表示されます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .task {
            await loadSupportedLocales()
        }
        .fileImporter(
            isPresented: $showVaultPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                settings.vaultPath = url.path
            }
        }
    }

    /// 検索テキストでフィルタリングしたロケール一覧（表示言語セクション用）
    private var searchFilteredLocales: [Locale] {
        guard !localeSearchText.isEmpty else { return supportedLocales }
        let query = localeSearchText.lowercased()
        return supportedLocales.filter { locale in
            let name = locale.localizedString(forIdentifier: locale.identifier) ?? ""
            return name.lowercased().contains(query)
                || locale.identifier.lowercased().contains(query)
        }
    }

    private func toggleLocale(_ identifier: String) {
        var enabled = settings.enabledLocaleIdentifiers
        if enabled.isEmpty {
            // 初回: 全言語から対象を除外 → 対象以外を全て有効にする
            enabled = Set(supportedLocales.map(\.identifier))
            enabled.remove(identifier)
        } else if enabled.contains(identifier) {
            enabled.remove(identifier)
            // 全て外されたら「すべて表示」に戻す
            if enabled.isEmpty { /* そのまま空セットでOK */ }
        } else {
            enabled.insert(identifier)
        }
        settings.enabledLocaleIdentifiers = enabled
    }

    private func loadSupportedLocales() async {
        isLoadingLocales = true
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocales = locales.sortedByLocalizedName()
        isLoadingLocales = false
    }
}
