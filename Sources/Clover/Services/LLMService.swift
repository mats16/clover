import Foundation

/// OpenAI 互換の Chat Completions API を呼び出すサービス。
enum LLMService {
    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct RequestBody: Codable {
        let model: String
        let max_tokens: Int
        let messages: [ChatMessage]
    }

    private struct ResponseBody: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String

                private struct ContentPart: Codable {
                    let type: String
                    let text: String?
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    if let stringValue = try? container.decode(String.self, forKey: .content) {
                        content = stringValue
                    } else if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                        content = parts.compactMap(\.text).joined()
                    } else {
                        content = ""
                    }
                }
            }

            let message: Message
        }

        let choices: [Choice]
    }

    /// 疎通確認。短いメッセージを送り、レスポンスが返ることを検証する。
    static func testConnection(endpoint: String, model: String, token: String) async throws {
        let messages = [ChatMessage(role: "user", content: "Hi")]
        _ = try await chatCompletion(endpoint: endpoint, model: model, token: token, messages: messages, maxTokens: 8)
    }

    /// Chat Completions API を呼び出し、アシスタントの返答テキストを返す。
    static func chatCompletion(
        endpoint: String,
        model: String,
        token: String,
        messages: [ChatMessage],
        maxTokens: Int = 1024
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidEndpointURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 270

        let body = RequestBody(model: model, max_tokens: maxTokens, messages: messages)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.unexpectedResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(statusCode: httpResponse.statusCode, detail: detail)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }
        return text
    }

    enum LLMError: LocalizedError {
        case invalidEndpointURL
        case unexpectedResponse
        case httpError(statusCode: Int, detail: String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidEndpointURL:
                L10n.llmErrorInvalidURL
            case .unexpectedResponse:
                L10n.llmErrorUnexpectedResponse
            case let .httpError(statusCode, detail):
                L10n.llmErrorHTTP(statusCode, detail)
            case .emptyResponse:
                L10n.llmErrorEmptyResponse
            }
        }
    }
}
