import SwiftUI

/// 設定画面「AI 要約」タブ。LLM エンドポイントを管理する。
struct AISummarySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiToken = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    private enum ConnectionTestResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.aiSummary)
                .font(.title)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)

        Form {
            Section {
                LabeledContent(L10n.endpointURL) {
                    TextField("", text: $settings.llmEndpointURL, prompt: Text("https://…/mlflow/v1/chat/completions"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }

                LabeledContent(L10n.modelName) {
                    TextField("", text: $settings.llmModelName, prompt: Text("databricks-gpt-5-4"))
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent(L10n.apiToken) {
                    SecureField("", text: $apiToken)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { settings.llmAPIToken = apiToken }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.apiTokenStoredInKeychain)
                        .foregroundStyle(.secondary)

                    HStack {
                        if let result = connectionTestResult {
                            switch result {
                            case .success:
                                Label(L10n.connectionSuccess, systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case let .failure(message):
                                Label(message, systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        Spacer()
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.testing)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(L10n.testConnection) {
                                testConnection()
                            }
                            .disabled(!isLLMConfigComplete)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            apiToken = settings.llmAPIToken
        }
        .onDisappear {
            settings.llmAPIToken = apiToken
        }

        } // VStack
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
}
