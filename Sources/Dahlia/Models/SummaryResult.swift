import Foundation

/// LLM の structured output で返される要約結果。
struct SummaryResult: Codable {
    let title: String
    let summary: String
    let tags: [String]
    let actionItems: [SummaryActionItem]

    init(title: String, summary: String, tags: [String], actionItems: [SummaryActionItem] = []) {
        self.title = title
        self.summary = summary
        self.tags = tags
        self.actionItems = actionItems
    }

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
                "action_items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "assignee": ["type": "string"],
                        ],
                        "required": ["title", "assignee"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["title", "summary", "tags", "action_items"],
            "additionalProperties": false,
        ]
        let schemaData = try! JSONSerialization.data(withJSONObject: schema)
        return LLMService.ResponseFormat(
            type: "json_schema",
            json_schema: .init(name: "summary_result", strict: true, schemaData: schemaData)
        )
    }()

    private enum CodingKeys: String, CodingKey {
        case title
        case summary
        case tags
        case actionItems = "action_items"
    }
}
