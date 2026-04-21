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
