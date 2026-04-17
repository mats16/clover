import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
import Testing

struct MeetingRepositoryActionItemsTests {
    @Test
    func generatedSummaryPersistsActionItemsAndPreservesCompletion() throws {
        let context = try makeRepositoryContext()

        try context.repo.applyGeneratedSummary(
            toMeetingId: context.meeting.id,
            title: "Weekly sync",
            summary: "Summary body",
            tags: ["team"],
            actionItems: [
                SummaryActionItem(title: "Send notes", assignee: "me"),
                SummaryActionItem(title: "Book next meeting", assignee: "Alex"),
            ]
        )

        let initialItems = try context.repo.fetchActionItems(forMeetingId: context.meeting.id)
        let sendNotes = try #require(initialItems.first(where: { $0.title == "Send notes" }))
        try context.repo.setActionItemCompleted(id: sendNotes.id, isCompleted: true)

        try context.repo.applyGeneratedSummary(
            toMeetingId: context.meeting.id,
            title: "Weekly sync",
            summary: "Updated summary body",
            tags: ["team"],
            actionItems: [
                SummaryActionItem(title: "Send notes", assignee: "me"),
                SummaryActionItem(title: "Share recording", assignee: ""),
            ]
        )

        let reloadedItems = try context.repo.fetchActionItems(forMeetingId: context.meeting.id)
        let detail = try context.repo.fetchMeetingDetail(id: context.meeting.id)

        #expect(reloadedItems.count == 2)
        #expect(reloadedItems.first(where: { $0.title == "Send notes" })?.isCompleted == true)
        #expect(reloadedItems.first(where: { $0.title == "Share recording" })?.isCompleted == false)
        #expect(reloadedItems.allSatisfy { $0.title != "Book next meeting" })
        #expect(detail.actionItems.map(\.title).sorted() == ["Send notes", "Share recording"])
    }

    @Test
    func deletingMeetingCascadesActionItems() throws {
        let context = try makeRepositoryContext()

        try context.repo.applyGeneratedSummary(
            toMeetingId: context.meeting.id,
            title: "Weekly sync",
            summary: "Summary body",
            tags: [],
            actionItems: [
                SummaryActionItem(title: "Send notes", assignee: "me"),
            ]
        )

        try context.repo.deleteMeeting(id: context.meeting.id)

        let remainingItems = try context.repo.fetchActionItems(forMeetingId: context.meeting.id)

        #expect(remainingItems.isEmpty)
    }

    @Test
    func updatingActionItemAssigneeReplacesExistingValue() throws {
        let context = try makeRepositoryContext()

        try context.repo.applyGeneratedSummary(
            toMeetingId: context.meeting.id,
            title: "Weekly sync",
            summary: "Summary body",
            tags: [],
            actionItems: [
                SummaryActionItem(title: "Book next meeting", assignee: "Alex"),
            ]
        )

        let actionItem = try #require(context.repo.fetchActionItems(forMeetingId: context.meeting.id).first)

        try context.repo.setActionItemAssignee(id: actionItem.id, assignee: "  me  ")
        #expect(context.repo.fetchActionItems(forMeetingId: context.meeting.id).first?.assignee == "me")

        try context.repo.setActionItemAssignee(id: actionItem.id, assignee: "")
        #expect(context.repo.fetchActionItems(forMeetingId: context.meeting.id).first?.assignee == "")
    }

    private func makeRepositoryContext() throws -> RepositoryContext {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let manager = try AppDatabaseManager(path: databaseURL.path)
        let repo = MeetingRepository(dbQueue: manager.dbQueue)

        let vault = VaultRecord(
            id: .v7(),
            path: databaseURL.deletingPathExtension().path,
            name: "Test Vault",
            createdAt: Date(),
            lastOpenedAt: Date()
        )
        try repo.insertVault(vault)

        let meeting = MeetingRecord(
            id: .v7(),
            vaultId: vault.id,
            projectId: nil,
            name: "Weekly sync",
            createdAt: Date(),
            updatedAt: Date()
        )
        try manager.dbQueue.write { db in
            try meeting.insert(db)
        }

        return RepositoryContext(repo: repo, meeting: meeting)
    }

    private struct RepositoryContext {
        let repo: MeetingRepository
        let meeting: MeetingRecord
    }
}
#endif
