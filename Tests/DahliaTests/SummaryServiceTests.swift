import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

struct SummaryServiceTests {
    @Test
    func sanitizeBulletPointSummaryRemovesObsidianSyntax() {
        let input = """
        ## Summary

        - Decide to ship ([[meeting#00:10:00|00:10:00]])
        - See ![[capture-1.webp]]
        - Ref [[internal-note]]
        - ![[capture-2.webp]]
        """

        let sanitized = SummaryService.sanitizeBulletPointSummary(input)

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
