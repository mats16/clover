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

    @Test
    func orderedCurrentMeetingActionItemsPrioritizeIncompleteMine() {
        let viewModel = CaptionViewModel()
        let meetingId = UUID.v7()

        viewModel.currentMeetingActionItems = [
            ActionItemRecord(id: .v7(), meetingId: meetingId, title: "Done task", assignee: "Alex", isCompleted: true),
            ActionItemRecord(id: .v7(), meetingId: meetingId, title: "Other task", assignee: "Alex", isCompleted: false),
            ActionItemRecord(id: .v7(), meetingId: meetingId, title: "Mine explicit", assignee: "me", isCompleted: false),
            ActionItemRecord(id: .v7(), meetingId: meetingId, title: "Mine implicit", assignee: "", isCompleted: false),
        ]

        #expect(viewModel.orderedCurrentMeetingActionItems.map(\.title) == [
            "Mine explicit",
            "Mine implicit",
            "Other task",
            "Done task",
        ])
    }

    @Test
    func clearCurrentMeetingResetsActionItems() {
        let viewModel = CaptionViewModel()
        let meetingId = UUID.v7()

        viewModel.currentMeetingId = meetingId
        viewModel.currentMeetingActionItems = [
            ActionItemRecord(id: .v7(), meetingId: meetingId, title: "Follow up", assignee: "me", isCompleted: false),
        ]

        viewModel.clearCurrentMeeting()

        #expect(viewModel.currentMeetingActionItems.isEmpty)
    }

    @Test
    func emptyAssigneeIsNotExplicitlyAssignedToMe() {
        let actionItem = ActionItemRecord(
            id: .v7(),
            meetingId: .v7(),
            title: "Follow up",
            assignee: "",
            isCompleted: false
        )

        #expect(actionItem.sortsAsMine)
        #expect(!actionItem.isExplicitlyAssignedToMe)
    }

    @Test
    func explicitMeAssigneeIsRecognized() {
        let actionItem = ActionItemRecord(
            id: .v7(),
            meetingId: .v7(),
            title: "Follow up",
            assignee: "me",
            isCompleted: false
        )

        #expect(actionItem.sortsAsMine)
        #expect(actionItem.isExplicitlyAssignedToMe)
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
