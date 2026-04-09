import Foundation

/// LLM の structured output で返される要約結果。
struct SummaryResult: Codable {
    let title: String
    let summary: String
    let tags: [String]

    /// OpenAI 互換 API の `response_format` パラメータ用 JSON Schema。
    static let responseFormat: LLMService.ResponseFormat = {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
            ],
            "required": ["title", "summary", "tags"],
            "additionalProperties": false,
        ]
        let schemaData = try! JSONSerialization.data(withJSONObject: schema)
        return LLMService.ResponseFormat(
            type: "json_schema",
            json_schema: .init(name: "summary_result", strict: true, schemaData: schemaData)
        )
    }()
}
