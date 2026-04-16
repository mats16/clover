import Foundation
@testable import Dahlia
#if canImport(Testing)
import Testing

struct MeetingOverviewFiltersTests {
    @Test
    func projectOptionsIncludeAllProjectsInVault() {
        let alphaId = UUID.v7()
        let betaId = UUID.v7()

        let options = MeetingOverviewFilters.projectOptions(
            from: [
                project(id: betaId, name: "Beta"),
                project(id: alphaId, name: "Alpha"),
            ]
        )

        #expect(options.map(\.name) == ["Alpha", "Beta"])
        #expect(Set(options.map(\.id)) == Set([alphaId, betaId]))
    }

    @Test
    func tagOptionsAreBuiltFromMeetingMetadata() {
        let meetings = [
            meeting(name: "Design Review", tags: [TagInfo(name: "design", colorHex: "#FF0000")]),
            meeting(name: "Sales Sync", tags: [TagInfo(name: "sales", colorHex: "#00FF00")]),
            meeting(name: "Retro", tags: [TagInfo(name: "design", colorHex: "#123456")]),
        ]

        let options = MeetingOverviewFilters.tagOptions(from: meetings)

        #expect(options.map(\.name) == ["design", "sales"])
        #expect(options.first?.colorHex == "#FF0000")
    }

    @Test
    func applyRequiresMeetingsToMatchSelectedProjectAndTag() {
        let alphaId = UUID.v7()
        let betaId = UUID.v7()
        let meetings = [
            meeting(
                projectId: alphaId,
                projectName: "Alpha",
                name: "Design Review",
                tags: [TagInfo(name: "design", colorHex: "#FF0000")],
            ),
            meeting(
                projectId: betaId,
                projectName: "Beta",
                name: "Design Review",
                tags: [TagInfo(name: "design", colorHex: "#FF0000")],
            ),
            meeting(
                projectId: alphaId,
                projectName: "Alpha",
                name: "Sales Sync",
                tags: [TagInfo(name: "sales", colorHex: "#00FF00")],
            ),
        ]
        let selection = MeetingOverviewFilterSelection(projectIds: [alphaId], tagNames: ["design"])

        let filtered = MeetingOverviewFilters.apply(selection: selection, to: meetings)

        #expect(filtered.map(\.meetingName) == ["Design Review"])
        #expect(filtered.first?.projectId == alphaId)
    }
}
#endif

private func project(id: UUID, name: String) -> ProjectOverviewItem {
    ProjectOverviewItem(
        projectId: id,
        projectName: name,
        createdAt: Date(),
        missingOnDisk: false,
        meetingCount: 0,
        latestMeetingDate: nil,
    )
}

private func meeting(
    projectId: UUID? = nil,
    projectName: String? = nil,
    name: String,
    tags: [TagInfo],
) -> MeetingOverviewItem {
    MeetingOverviewItem(
        meetingId: UUID.v7(),
        vaultId: UUID.v7(),
        projectId: projectId,
        projectName: projectName,
        meetingName: name,
        status: .ready,
        duration: nil,
        createdAt: Date(),
        hasSummary: false,
        segmentCount: 0,
        latestSegmentText: nil,
        tags: tags,
    )
}
