import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

struct SummaryServiceTests {
    @Test
    func summaryResultDecodesActionItems() throws {
        let json = """
        {
          "title": "Weekly sync",
          "summary": "Summary body",
          "tags": ["team"],
          "action_items": [
            {
              "title": "Send notes",
              "assignee": "me"
            }
          ]
        }
        """

        let result = try JSONDecoder().decode(SummaryResult.self, from: Data(json.utf8))

        #expect(result.title == "Weekly sync")
        #expect(result.actionItems == [SummaryActionItem(title: "Send notes", assignee: "me")])
    }

    @Test
    func summaryResultDefaultsActionItemsToEmpty() {
        let result = SummaryResult(title: "Title", summary: "Body", tags: ["team"])

        #expect(result.actionItems.isEmpty)
    }

    @Test
    func summaryResultSchemaRequiresActionItemsWithoutExtraFields() throws {
        let schemaData = try #require(SummaryResult.responseFormat.json_schema?.schemaData)
        let schemaObject = try JSONSerialization.jsonObject(with: schemaData)
        let schema = try #require(schemaObject as? [String: Any])
        let required = try #require(schema["required"] as? [String])
        let properties = try #require(schema["properties"] as? [String: Any])
        let actionItems = try #require(properties["action_items"] as? [String: Any])
        let items = try #require(actionItems["items"] as? [String: Any])

        #expect(required.contains("action_items"))
        #expect((items["additionalProperties"] as? Bool) == false)
    }

    @Test
    func sanitizeDisplaySummaryRemovesObsidianSyntax() {
        let input = """
        ## Summary

        - Decide to ship ([[meeting#00:10:00|00:10:00]])
        - See ![[capture-1.webp]]
        - Ref [[internal-note]]
        - ![[capture-2.webp]]
        """

        let sanitized = SummaryService.sanitizeDisplaySummary(input)

        #expect(!sanitized.contains("[["))
        #expect(!sanitized.contains("![["))
        #expect(sanitized.contains("00:10:00"))
        #expect(!sanitized.contains("internal-note"))
        #expect(!sanitized.contains("capture-2.webp"))
    }

    @Test
    func resolvedTagsDoesNotInjectAISummary() {
        let context = """
        ---
        tags:
          - customer_meeting
        ---
        """

        let tags = SummaryService.resolvedTags(
            resultTags: ["follow_up", "customer_meeting"],
            contextContent: context
        )

        #expect(tags == ["follow_up", "customer_meeting"])
        #expect(!tags.contains("ai_summary"))
    }
}
#endif
