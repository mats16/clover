import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
import Testing

@MainActor
struct CaptionViewModelTests {
    private let testVaultURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

    @Test
    func selectingActiveRecordingMeetingKeepsLiveTranscriptStore() throws {
        let viewModel = CaptionViewModel()
        let dbQueue = try DatabaseQueue(path: ":memory:")
        let meetingId = UUID.v7()
        let initialSegment = TranscriptSegment(
            startTime: Date(),
            text: "live transcript",
            isConfirmed: true,
            speakerLabel: "mic",
        )

        viewModel.isListening = true
        viewModel.currentMeetingId = meetingId
        viewModel.currentVaultURL = testVaultURL
        viewModel.store.loadSegments([initialSegment])

        let storeIdentity = ObjectIdentifier(viewModel.store)

        viewModel.loadMeeting(
            meetingId,
            dbQueue: dbQueue,
            projectURL: nil,
            projectId: nil,
            vaultURL: testVaultURL,
        )

        #expect(ObjectIdentifier(viewModel.store) == storeIdentity)
        #expect(viewModel.store.segments == [initialSegment])
        #expect(viewModel.recordingMeetingId == meetingId)
    }
}
#elseif canImport(XCTest)
import XCTest

@MainActor
final class CaptionViewModelTests: XCTestCase {
    private let testVaultURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

    func testSelectingActiveRecordingMeetingKeepsLiveTranscriptStore() throws {
        let viewModel = CaptionViewModel()
        let dbQueue = try DatabaseQueue(path: ":memory:")
        let meetingId = UUID.v7()
        let initialSegment = TranscriptSegment(
            startTime: Date(),
            text: "live transcript",
            isConfirmed: true,
            speakerLabel: "mic",
        )

        viewModel.isListening = true
        viewModel.currentMeetingId = meetingId
        viewModel.currentVaultURL = testVaultURL
        viewModel.store.loadSegments([initialSegment])

        let storeIdentity = ObjectIdentifier(viewModel.store)

        viewModel.loadMeeting(
            meetingId,
            dbQueue: dbQueue,
            projectURL: nil,
            projectId: nil,
            vaultURL: testVaultURL,
        )

        XCTAssertEqual(ObjectIdentifier(viewModel.store), storeIdentity)
        XCTAssertEqual(viewModel.store.segments, [initialSegment])
        XCTAssertEqual(viewModel.recordingMeetingId, meetingId)
    }
}
#endif
