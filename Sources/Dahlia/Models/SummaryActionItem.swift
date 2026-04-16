import Foundation

struct SummaryActionItem: Codable, Equatable {
    let title: String
    let assignee: String

    var isEmpty: Bool {
        normalizedTitle.isEmpty
    }

    var persistenceKey: String {
        normalizedTitle + "\u{1F}" + normalizedAssignee
    }

    var normalizedTitle: String {
        Self.normalize(title)
    }

    var normalizedAssignee: String {
        Self.normalize(assignee).lowercased()
    }

    static func normalizedAssignee(_ assignee: String) -> String {
        normalize(assignee).lowercased()
    }

    static let selfAssigneeKey = "me"
    private static let selfAssigneeAliases: Set = ["me", "自分"]

    static func isExplicitlyAssignedToMe(_ assignee: String) -> Bool {
        selfAssigneeAliases.contains(normalizedAssignee(assignee))
    }

    static func sortsAsMine(_ assignee: String) -> Bool {
        let normalized = normalizedAssignee(assignee)
        return normalized.isEmpty || selfAssigneeAliases.contains(normalized)
    }

    static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
