import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

@MainActor
struct TranscriptSegmentTests {
    @Test
    func transcriptStoreUpdatesTranslatedTextForMatchingSegmentOnly() {
        let store = TranscriptStore()
        let first = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_000),
            text: "First",
            isConfirmed: true,
            speakerLabel: "mic"
        )
        let second = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_100),
            text: "Second",
            isConfirmed: true,
            speakerLabel: "system"
        )

        store.loadSegments([first, second])
        store.updateTranslatedText(for: second.id, translatedText: "2つ目")

        #expect(store.segments[0].translatedText == nil)
        #expect(store.segments[1].translatedText == "2つ目")
    }

    @Test
    func transcriptStoreReusesUnconfirmedSegmentIDAndPreservesTranslatedText() {
        let store = TranscriptStore()
        let first = store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_000),
                text: "Hello",
                translatedText: "こんにちは",
                isConfirmed: false,
                speakerLabel: "mic"
            ),
            forSource: "mic"
        )
        let second = store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_001),
                text: "Hello world",
                isConfirmed: false,
                speakerLabel: "mic"
            ),
            forSource: "mic"
        )

        #expect(first.id == second.id)
        #expect(store.segments.count == 1)
        #expect(store.segments[0].id == first.id)
        #expect(store.segments[0].translatedText == "こんにちは")
        #expect(store.segments[0].text == "Hello world")
    }

    @Test
    func clearUnconfirmedSegmentsOnlyRemovesMatchingSource() {
        let store = TranscriptStore()
        store.loadSegments([
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_000),
                text: "Confirmed",
                isConfirmed: true,
                speakerLabel: "mic"
            ),
        ])
        store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_001),
                text: "Mic preview",
                isConfirmed: false,
                speakerLabel: "mic"
            ),
            forSource: "mic"
        )
        store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_002),
                text: "System preview",
                isConfirmed: false,
                speakerLabel: "system"
            ),
            forSource: "system"
        )

        store.clearUnconfirmedSegments(forSource: "mic")

        #expect(store.segments.count == 2)
        #expect(store.segments.contains(where: { $0.text == "Confirmed" && $0.isConfirmed }))
        #expect(store.segments.contains(where: { $0.text == "System preview" && !$0.isConfirmed }))
        #expect(!store.segments.contains(where: { $0.text == "Mic preview" }))
    }

    @Test
    func transcriptSegmentRecordRoundTripsTranslatedText() {
        let meetingID = UUID.v7()
        let segment = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_000),
            text: "Hello world",
            translatedText: "こんにちは、世界",
            isConfirmed: true,
            speakerLabel: "mic"
        )

        let record = TranscriptSegmentRecord(from: segment, meetingId: meetingID)
        let roundTripped = TranscriptSegment(from: record)

        #expect(record.translatedText == "こんにちは、世界")
        #expect(roundTripped.translatedText == "こんにちは、世界")
    }

    @Test
    func visibleTranslatedTextRespectsSettingAndBlankValues() {
        let segment = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_000),
            text: "Hello world",
            translatedText: " こんにちは、世界 ",
            isConfirmed: true
        )
        let blankSegment = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_100),
            text: "Hello world",
            translatedText: "  ",
            isConfirmed: true
        )

        #expect(segment.visibleTranslatedText(isEnabled: true) == "こんにちは、世界")
        #expect(segment.visibleTranslatedText(isEnabled: false) == nil)
        #expect(blankSegment.visibleTranslatedText(isEnabled: true) == nil)
    }
}
#elseif canImport(XCTest)
import XCTest

@MainActor
final class TranscriptSegmentTests: XCTestCase {
    func testTranscriptStoreUpdatesTranslatedTextForMatchingSegmentOnly() {
        let store = TranscriptStore()
        let first = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_000),
            text: "First",
            isConfirmed: true,
            speakerLabel: "mic"
        )
        let second = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_100),
            text: "Second",
            isConfirmed: true,
            speakerLabel: "system"
        )

        store.loadSegments([first, second])
        store.updateTranslatedText(for: second.id, translatedText: "2つ目")

        XCTAssertNil(store.segments[0].translatedText)
        XCTAssertEqual(store.segments[1].translatedText, "2つ目")
    }

    func testTranscriptStoreReusesUnconfirmedSegmentIDAndPreservesTranslatedText() {
        let store = TranscriptStore()
        let first = store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_000),
                text: "Hello",
                translatedText: "こんにちは",
                isConfirmed: false,
                speakerLabel: "mic"
            ),
            forSource: "mic"
        )
        let second = store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_001),
                text: "Hello world",
                isConfirmed: false,
                speakerLabel: "mic"
            ),
            forSource: "mic"
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.segments.count, 1)
        XCTAssertEqual(store.segments[0].id, first.id)
        XCTAssertEqual(store.segments[0].translatedText, "こんにちは")
        XCTAssertEqual(store.segments[0].text, "Hello world")
    }

    func testClearUnconfirmedSegmentsOnlyRemovesMatchingSource() {
        let store = TranscriptStore()
        store.loadSegments([
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_000),
                text: "Confirmed",
                isConfirmed: true,
                speakerLabel: "mic"
            ),
        ])
        store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_001),
                text: "Mic preview",
                isConfirmed: false,
                speakerLabel: "mic"
            ),
            forSource: "mic"
        )
        store.updateUnconfirmedSegment(
            TranscriptSegment(
                startTime: Date(timeIntervalSince1970: 1_776_384_002),
                text: "System preview",
                isConfirmed: false,
                speakerLabel: "system"
            ),
            forSource: "system"
        )

        store.clearUnconfirmedSegments(forSource: "mic")

        XCTAssertEqual(store.segments.count, 2)
        XCTAssertTrue(store.segments.contains(where: { $0.text == "Confirmed" && $0.isConfirmed }))
        XCTAssertTrue(store.segments.contains(where: { $0.text == "System preview" && !$0.isConfirmed }))
        XCTAssertFalse(store.segments.contains(where: { $0.text == "Mic preview" }))
    }

    func testTranscriptSegmentRecordRoundTripsTranslatedText() {
        let meetingID = UUID.v7()
        let segment = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_000),
            text: "Hello world",
            translatedText: "こんにちは、世界",
            isConfirmed: true,
            speakerLabel: "mic"
        )

        let record = TranscriptSegmentRecord(from: segment, meetingId: meetingID)
        let roundTripped = TranscriptSegment(from: record)

        XCTAssertEqual(record.translatedText, "こんにちは、世界")
        XCTAssertEqual(roundTripped.translatedText, "こんにちは、世界")
    }

    func testVisibleTranslatedTextRespectsSettingAndBlankValues() {
        let segment = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_000),
            text: "Hello world",
            translatedText: " こんにちは、世界 ",
            isConfirmed: true
        )
        let blankSegment = TranscriptSegment(
            startTime: Date(timeIntervalSince1970: 1_776_384_100),
            text: "Hello world",
            translatedText: "  ",
            isConfirmed: true
        )

        XCTAssertEqual(segment.visibleTranslatedText(isEnabled: true), "こんにちは、世界")
        XCTAssertNil(segment.visibleTranslatedText(isEnabled: false))
        XCTAssertNil(blankSegment.visibleTranslatedText(isEnabled: true))
    }
}
#endif
