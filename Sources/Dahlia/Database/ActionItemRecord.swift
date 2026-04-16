import Foundation
import GRDB

struct ActionItemRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "action_items"

    var id: UUID
    var meetingId: UUID
    var title: String
    var assignee: String
    var isCompleted: Bool

    var sortsAsMine: Bool {
        SummaryActionItem.sortsAsMine(assignee)
    }

    var isExplicitlyAssignedToMe: Bool {
        SummaryActionItem.isExplicitlyAssignedToMe(assignee)
    }

    var persistenceKey: String {
        SummaryActionItem(title: title, assignee: assignee).persistenceKey
    }
}
