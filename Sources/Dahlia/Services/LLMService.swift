import Foundation

/// OpenAI 互換の Chat Completions API を呼び出すサービス。
enum LLMService {
    // MARK: - Response Format (Structured Outputs)

    /// `response_format` パラメータ。`json_schema` の `schema` は生の JSON Data で保持する。
    struct ResponseFormat: Encodable {
        let type: String
        let json_schema: JSONSchemaSpec?

        struct JSONSchemaSpec: Encodable {
            let name: String
            let strict: Bool
            /// JSON Schema を表す生の JSON バイト列。
            let schemaData: Data

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(strict, forKey: .strict)
                // schemaData を JSON オブジェクトとしてそのまま埋め込む
                let rawSchema = try JSONSerialization.jsonObject(with: schemaData)
                try container.encode(AnyEncodable(rawSchema), forKey: .schema)
            }

            private enum CodingKeys: String, CodingKey {
                case name, strict, schema
            }
        }
    }

    /// 任意の JSON-compatible な値を `Encodable` としてラップする。
    private struct AnyEncodable: Encodable {
        let value: Any

        init(_ value: Any) { self.value = value }

        func encode(to encoder: Encoder) throws {
            switch value {
            case let string as String:
                var c = encoder.singleValueContainer()
                try c.encode(string)
            case let bool as Bool:
                var c = encoder.singleValueContainer()
                try c.encode(bool)
            case let int as Int:
                var c = encoder.singleValueContainer()
                try c.encode(int)
            case let double as Double:
                var c = encoder.singleValueContainer()
                try c.encode(double)
            case let array as [Any]:
                var c = encoder.unkeyedContainer()
                for item in array { try c.encode(AnyEncodable(item)) }
            case let dict as [String: Any]:
                var c = encoder.container(keyedBy: DynamicKey.self)
                for (key, val) in dict {
                    try c.encode(AnyEncodable(val), forKey: DynamicKey(key))
                }
            default:
                var c = encoder.singleValueContainer()
                try c.encodeNil()
            }
        }

        private struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ string: String) { self.stringValue = string }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue _: Int) { nil }
        }
    }

    // MARK: - Content Types

    enum ContentPart {
        case text(String)
        case imageURL(String) // data URI (e.g. "data:image/webp;base64,...")
    }

    enum ChatMessageContent {
        case text(String)
        case parts([ContentPart])
    }

    struct ChatMessage: Encodable {
        let role: String
        let content: ChatMessageContent

        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
        }

        init(role: String, parts: [ContentPart]) {
            self.role = role
            self.content = .parts(parts)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            switch content {
            case let .text(string):
                try container.encode(string, forKey: .content)
            case let .parts(parts):
                var partsContainer = container.nestedUnkeyedContainer(forKey: .content)
                for part in parts {
                    switch part {
                    case let .text(text):
                        try partsContainer.encode(TextPart(type: "text", text: text))
                    case let .imageURL(url):
                        try partsContainer.encode(ImageURLPart(type: "image_url", image_url: .init(url: url)))
                    }
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case role, content
        }

        private struct TextPart: Encodable {
            let type: String
            let text: String
        }

        private struct ImageURLPart: Encodable {
            let type: String
            let image_url: ImageURL

            struct ImageURL: Encodable {
                let url: String
            }
        }
    }

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [ChatMessage]
        var response_format: ResponseFormat? = nil

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(max_tokens, forKey: .max_tokens)
            try container.encode(messages, forKey: .messages)
            try container.encodeIfPresent(response_format, forKey: .response_format)
        }

        private enum CodingKeys: String, CodingKey {
            case model, max_tokens, messages, response_format
        }
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
        maxTokens: Int = 1024,
        responseFormat: ResponseFormat? = nil
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidEndpointURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 270

        let body = RequestBody(model: model, max_tokens: maxTokens, messages: messages, response_format: responseFormat)
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
