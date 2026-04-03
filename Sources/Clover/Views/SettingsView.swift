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
    @State private var apiToken = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    private enum ConnectionTestResult {
        case success
        case failure(String)
    }

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

            Section {
                LabeledContent(L10n.endpointURL) {
                    TextField("", text: $settings.llmEndpointURL)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent(L10n.modelName) {
                    TextField("", text: $settings.llmModelName)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent(L10n.apiToken) {
                    SecureField("", text: $apiToken)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { settings.llmAPIToken = apiToken }
                }

                HStack {
                    Text(L10n.apiTokenStoredInKeychain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.testing)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button(L10n.testConnection) {
                            testConnection()
                        }
                        .font(.caption)
                        .disabled(!isLLMConfigComplete)
                    }
                }

                if let result = connectionTestResult {
                    switch result {
                    case .success:
                        Label(L10n.connectionSuccess, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Toggle(L10n.autoSummary, isOn: $settings.llmAutoSummaryEnabled)

                Text(L10n.autoSummaryDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.summaryPrompt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $settings.llmSummaryPrompt)
                        .font(.body)
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.3))
                    HStack {
                        Spacer()
                        Button(L10n.resetToDefault) {
                            settings.llmSummaryPrompt = AppSettings.defaultSummaryPrompt
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Text(L10n.llmSettings)
            } footer: {
                Text(L10n.llmSettingsDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                if isLoadingLocales {
                    ProgressView(L10n.loadingLanguages)
                        .font(.caption)
                } else {
                    TextField(L10n.searchLanguages, text: $localeSearchText)
                        .textFieldStyle(.roundedBorder)

                    let searchedLocales = searchFilteredLocales
                    if searchedLocales.isEmpty {
                        Text(L10n.noMatchingLanguages)
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
                             ? L10n.allLanguagesShown
                             : L10n.languagesSelected(enabledCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !settings.enabledLocaleIdentifiers.isEmpty {
                            Button(L10n.showAll) {
                                settings.enabledLocaleIdentifiers = []
                            }
                            .font(.caption)
                        }
                    }
                }
            } header: {
                Text(L10n.displayLanguages)
            } footer: {
                Text(L10n.displayLanguagesDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .padding()
        .task {
            apiToken = settings.llmAPIToken
            await loadSupportedLocales()
        }
        .onDisappear {
            settings.llmAPIToken = apiToken
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

    private var isLLMConfigComplete: Bool {
        !settings.llmEndpointURL.isEmpty && !settings.llmModelName.isEmpty && !apiToken.isEmpty
    }

    private func testConnection() {
        settings.llmAPIToken = apiToken
        connectionTestResult = nil
        isTestingConnection = true
        Task {
            do {
                try await LLMService.testConnection(
                    endpoint: settings.llmEndpointURL,
                    model: settings.llmModelName,
                    token: apiToken
                )
                connectionTestResult = .success
            } catch {
                connectionTestResult = .failure(error.localizedDescription)
            }
            isTestingConnection = false
        }
    }

    private func loadSupportedLocales() async {
        isLoadingLocales = true
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocales = locales.sortedByLocalizedName()
        isLoadingLocales = false
    }
}
