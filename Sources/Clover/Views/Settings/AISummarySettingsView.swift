import SwiftUI

/// 設定画面「AI 要約」タブ。LLM エンドポイント・テンプレートを管理する。
struct AISummarySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiToken = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var templates: [SummaryTemplate] = []

    private enum ConnectionTestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
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
                    case let .failure(message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text(L10n.model)
            } footer: {
                Text(L10n.llmSettingsDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle(L10n.autoSummary, isOn: $settings.llmAutoSummaryEnabled)

                Text(L10n.autoSummaryDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n.autoSummary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.summaryTemplate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $settings.selectedTemplateName) {
                        ForEach(templates) { template in
                            Text(template.displayName).tag(template.name)
                        }
                    }

                    HStack {
                        Button(L10n.openInEditor) { openSelectedTemplateInEditor() }
                        Button(L10n.openTemplatesFolder) { openTemplatesFolder() }
                        Spacer()
                        Button(L10n.resetPresets) { resetPresets() }
                    }
                    .font(.caption)

                    Text(L10n.summaryTemplateDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(L10n.templates)
            }
        }
        .formStyle(.grouped)
        .task {
            apiToken = settings.llmAPIToken
            loadTemplates()
        }
        .onChange(of: settings.vaultPath) {
            loadTemplates()
        }
        .onDisappear {
            settings.llmAPIToken = apiToken
        }
    }

    // MARK: - Private

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

    private let templateService = SummaryTemplateService()

    private func loadTemplates() {
        let vaultURL = settings.vaultURL
        try? templateService.seedPresets(in: vaultURL)
        templates = (try? templateService.fetchTemplates(in: vaultURL)) ?? []
        if !templates.contains(where: { $0.name == settings.selectedTemplateName }),
           let first = templates.first {
            settings.selectedTemplateName = first.name
        }
    }

    private func openSelectedTemplateInEditor() {
        guard let template = templates.first(where: { $0.name == settings.selectedTemplateName }) else { return }
        NSWorkspace.shared.open(template.url)
    }

    private func openTemplatesFolder() {
        let dir = SummaryTemplateService.templatesDirectoryURL(in: settings.vaultURL)
        NSWorkspace.shared.open(dir)
    }

    private func resetPresets() {
        try? templateService.resetPresets(in: settings.vaultURL)
    }
}
