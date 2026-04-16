import Foundation

struct MeetingOverviewFilterSelection: Equatable {
    var projectIds: Set<UUID> = []
    var tagNames: Set<String> = []

    var isEmpty: Bool {
        projectIds.isEmpty && tagNames.isEmpty
    }
}

struct MeetingOverviewProjectOption: Equatable, Identifiable {
    let id: UUID
    let name: String
}

enum MeetingOverviewFilters {
    static func projectOptions(from projects: [ProjectOverviewItem]) -> [MeetingOverviewProjectOption] {
        projects
            .map { MeetingOverviewProjectOption(id: $0.projectId, name: $0.projectName) }
            .sorted { lhs, rhs in
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return comparison == .orderedAscending
            }
    }

    static func tagOptions(from meetings: [MeetingOverviewItem]) -> [TagInfo] {
        var tagsByName: [String: TagInfo] = [:]

        for meeting in meetings {
            for tag in meeting.tags where tagsByName[tag.name] == nil {
                tagsByName[tag.name] = tag
            }
        }

        return tagsByName.values.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.colorHex < rhs.colorHex
            }
            return comparison == .orderedAscending
        }
    }

    static func apply(
        selection: MeetingOverviewFilterSelection,
        to meetings: [MeetingOverviewItem]
    ) -> [MeetingOverviewItem] {
        meetings.filter { meeting in
            let matchesProject: Bool = if selection.projectIds.isEmpty {
                true
            } else if let projectId = meeting.projectId {
                selection.projectIds.contains(projectId)
            } else {
                false
            }

            let matchesTags = selection.tagNames.isEmpty || meeting.tags.contains {
                selection.tagNames.contains($0.name)
            }

            return matchesProject && matchesTags
        }
    }
}
