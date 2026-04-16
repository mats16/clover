import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

@MainActor
struct SidebarViewModelSelectionTests {
    @Test
    func toggleSelectionDoesNotOpenMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let meetingId = UUID.v7()
            let projectId = UUID.v7()

            viewModel.toggleMeetingSelection(meetingId, projectId: projectId, projectName: "Meetings")

            #expect(viewModel.selectedMeetingId == nil)
            #expect(viewModel.selectedMeetingIds == Set([meetingId]))
        }
    }

    @Test
    func toggleSelectionClearsOpenedMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let projectId = UUID.v7()
            let firstMeetingId = UUID.v7()
            let secondMeetingId = UUID.v7()

            viewModel.singleSelectMeeting(firstMeetingId, projectId: projectId, projectName: "Meetings")
            viewModel.toggleMeetingSelection(secondMeetingId, projectId: projectId, projectName: "Meetings")

            #expect(viewModel.selectedMeetingId == nil)
            #expect(viewModel.selectedMeetingIds == Set([firstMeetingId, secondMeetingId]))
        }
    }

    @Test
    func rangeSelectionUsesAnchorWithoutOpeningMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let projectId = UUID.v7()
            let firstMeetingId = UUID.v7()
            let secondMeetingId = UUID.v7()
            let thirdMeetingId = UUID.v7()

            viewModel.meetingsForProject[projectId] = [
                testMeeting(id: firstMeetingId, projectId: projectId),
                testMeeting(id: secondMeetingId, projectId: projectId),
                testMeeting(id: thirdMeetingId, projectId: projectId),
            ]

            viewModel.toggleMeetingSelection(firstMeetingId, projectId: projectId, projectName: "Meetings")
            viewModel.rangeSelectMeeting(thirdMeetingId, projectId: projectId, projectName: "Meetings")

            #expect(viewModel.selectedMeetingId == nil)
            #expect(viewModel.selectedMeetingIds == Set([firstMeetingId, secondMeetingId, thirdMeetingId]))
        }
    }

    @Test
    func singleSelectionStillOpensMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let meetingId = UUID.v7()
            let projectId = UUID.v7()

            viewModel.singleSelectMeeting(meetingId, projectId: projectId, projectName: "Meetings")

            #expect(viewModel.selectedMeetingId == meetingId)
            #expect(viewModel.selectedMeetingIds == Set([meetingId]))
        }
    }

    @Test
    func reselectingProjectsReturnsToProjectsOverview() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let projectId = UUID.v7()
            let meetingId = UUID.v7()

            viewModel.selectedDestination = .projects
            viewModel.selectProject(id: projectId, name: "Projects")
            viewModel.selectMeeting(meetingId)
            viewModel.selectedProjectIds = [projectId]

            viewModel.selectDestination(.projects)

            #expect(viewModel.selectedProject == nil)
            #expect(viewModel.selectedMeetingId == nil)
            #expect(viewModel.selectedProjectIds.isEmpty)
        }
    }
}
#elseif canImport(XCTest)
import XCTest

@MainActor
final class SidebarViewModelSelectionTests: XCTestCase {
    func testToggleSelectionDoesNotOpenMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let meetingId = UUID.v7()
            let projectId = UUID.v7()

            viewModel.toggleMeetingSelection(meetingId, projectId: projectId, projectName: "Meetings")

            XCTAssertNil(viewModel.selectedMeetingId)
            XCTAssertEqual(viewModel.selectedMeetingIds, Set([meetingId]))
        }
    }

    func testToggleSelectionClearsOpenedMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let projectId = UUID.v7()
            let firstMeetingId = UUID.v7()
            let secondMeetingId = UUID.v7()

            viewModel.singleSelectMeeting(firstMeetingId, projectId: projectId, projectName: "Meetings")
            viewModel.toggleMeetingSelection(secondMeetingId, projectId: projectId, projectName: "Meetings")

            XCTAssertNil(viewModel.selectedMeetingId)
            XCTAssertEqual(viewModel.selectedMeetingIds, Set([firstMeetingId, secondMeetingId]))
        }
    }

    func testRangeSelectionUsesAnchorWithoutOpeningMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let projectId = UUID.v7()
            let firstMeetingId = UUID.v7()
            let secondMeetingId = UUID.v7()
            let thirdMeetingId = UUID.v7()

            viewModel.meetingsForProject[projectId] = [
                testMeeting(id: firstMeetingId, projectId: projectId),
                testMeeting(id: secondMeetingId, projectId: projectId),
                testMeeting(id: thirdMeetingId, projectId: projectId),
            ]

            viewModel.toggleMeetingSelection(firstMeetingId, projectId: projectId, projectName: "Meetings")
            viewModel.rangeSelectMeeting(thirdMeetingId, projectId: projectId, projectName: "Meetings")

            XCTAssertNil(viewModel.selectedMeetingId)
            XCTAssertEqual(viewModel.selectedMeetingIds, Set([firstMeetingId, secondMeetingId, thirdMeetingId]))
        }
    }

    func testSingleSelectionStillOpensMeetingDetail() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let meetingId = UUID.v7()
            let projectId = UUID.v7()

            viewModel.singleSelectMeeting(meetingId, projectId: projectId, projectName: "Meetings")

            XCTAssertEqual(viewModel.selectedMeetingId, meetingId)
            XCTAssertEqual(viewModel.selectedMeetingIds, Set([meetingId]))
        }
    }

    func testReselectingProjectsReturnsToProjectsOverview() {
        withTestVault {
            let viewModel = SidebarViewModel()
            let projectId = UUID.v7()
            let meetingId = UUID.v7()

            viewModel.selectedDestination = .projects
            viewModel.selectProject(id: projectId, name: "Projects")
            viewModel.selectMeeting(meetingId)
            viewModel.selectedProjectIds = [projectId]

            viewModel.selectDestination(.projects)

            XCTAssertNil(viewModel.selectedProject)
            XCTAssertNil(viewModel.selectedMeetingId)
            XCTAssertTrue(viewModel.selectedProjectIds.isEmpty)
        }
    }
}
#endif

// MARK: - Shared Test Helpers

@MainActor
private func withTestVault(_ body: () -> Void) {
    let previousVault = AppSettings.shared.currentVault
    AppSettings.shared.currentVault = VaultRecord(
        id: .v7(),
        path: NSTemporaryDirectory(),
        name: "Test Vault",
        createdAt: Date(),
        lastOpenedAt: Date()
    )
    defer { AppSettings.shared.currentVault = previousVault }
    body()
}

@MainActor
private func testMeeting(id: UUID, projectId: UUID) -> MeetingRecord {
    MeetingRecord(
        id: id,
        vaultId: UUID.v7(),
        projectId: projectId,
        name: "",
        status: .ready,
        createdAt: Date(),
        updatedAt: Date()
    )
}
