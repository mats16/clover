import Foundation
import GRDB

struct ActionItemOverviewItem: Equatable, FetchableRecord, Identifiable {
    var actionItemId: UUID
    var meetingId: UUID
    var projectId: UUID?
    var projectName: String?
    var meetingName: String
    var meetingCreatedAt: Date
    var title: String
    var assignee: String
    var isCompleted: Bool

    var id: UUID { actionItemId }

    var sortsAsMine: Bool {
        SummaryActionItem.sortsAsMine(assignee)
    }

    var isExplicitlyAssignedToMe: Bool {
        SummaryActionItem.isExplicitlyAssignedToMe(assignee)
    }

    init(row: Row) throws {
        actionItemId = row["actionItemId"]
        meetingId = row["meetingId"]
        projectId = row["projectId"]
        projectName = row["projectName"]
        meetingName = row["meetingName"]
        meetingCreatedAt = row["meetingCreatedAt"]
        title = row["title"]
        assignee = row["assignee"]
        isCompleted = row["isCompleted"]
    }
}
