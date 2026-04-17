import SwiftUI

struct ActionItemsOverviewView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case open
        case mine
        case completed

        var id: Self { self }

        var title: String {
            switch self {
            case .all:
                L10n.all
            case .open:
                L10n.open
            case .mine:
                L10n.assignedToMe
            case .completed:
                L10n.completed
            }
        }
    }

    var sidebarViewModel: SidebarViewModel

    @State private var filter: Filter = .all

    private var actionItems: [ActionItemOverviewItem] {
        switch filter {
        case .all:
            sidebarViewModel.allActionItems
        case .open:
            sidebarViewModel.allActionItems.filter { !$0.isCompleted }
        case .mine:
            sidebarViewModel.allActionItems.filter(\.sortsAsMine)
        case .completed:
            sidebarViewModel.allActionItems.filter(\.isCompleted)
        }
    }

    private var hasActiveFilter: Bool {
        filter != .all
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.actionItems)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.primary)

                    Menu {
                        ForEach(Filter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                if option == filter {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Label(L10n.filter, systemImage: "line.3.horizontal.decrease")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                if actionItems.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.noActionItemsYet, systemImage: SidebarDestination.actionItems.systemImage)
                    } description: {
                        Text(hasActiveFilter ? L10n.noActionItemsMatchFilter : L10n.actionItemsDescription)
                    } actions: {
                        if hasActiveFilter {
                            Button(L10n.all, action: resetFilter)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(actionItems) { item in
                            ActionItemsOverviewRow(
                                item: item,
                                onToggleCompleted: { isCompleted in
                                    sidebarViewModel.setActionItemCompleted(id: item.actionItemId, isCompleted: isCompleted)
                                },
                                onSetAssignee: { assignee in
                                    sidebarViewModel.setActionItemAssignee(
                                        id: item.actionItemId,
                                        assignee: assignee
                                    )
                                },
                                onDelete: {
                                    sidebarViewModel.deleteActionItem(id: item.actionItemId)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }

    private func resetFilter() {
        filter = .all
    }
}

private struct ActionItemsOverviewRow: View {
    let item: ActionItemOverviewItem
    let onToggleCompleted: (Bool) -> Void
    let onSetAssignee: (String) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var meetingDisplayName: String {
        let trimmed = item.meetingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.newMeeting : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActionItemRowContent(
                title: item.title,
                assignee: item.assignee,
                isCompleted: item.isCompleted,
                onToggleCompleted: { onToggleCompleted(!item.isCompleted) },
                onSetAssignee: onSetAssignee,
                onDelete: onDelete
            )

            HStack(spacing: 10) {
                if let projectName = item.projectName,
                   !projectName.isEmpty {
                    Label(projectName, systemImage: "folder")
                }
                Label(meetingDisplayName, systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 32)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color(nsColor: .controlBackgroundColor))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
