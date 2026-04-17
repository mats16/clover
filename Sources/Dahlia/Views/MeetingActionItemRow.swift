import SwiftUI

struct ActionItemRowContent: View {
    let title: String
    let assignee: String
    let isCompleted: Bool
    let isExplicitlyAssignedToMe: Bool
    let onToggleCompleted: () -> Void
    let onToggleAssignedToMe: () -> Void
    let onDelete: () -> Void

    @State private var isAssigneeHovering = false

    private var trimmedAssignee: String {
        assignee.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var completionLabel: String {
        isCompleted ? L10n.markActionItemIncomplete : L10n.markActionItemComplete
    }

    private var assigneeActionLabel: String {
        isExplicitlyAssignedToMe ? L10n.removeAssignee : L10n.assignToMe
    }

    @ViewBuilder
    private var assigneeLabel: some View {
        if isExplicitlyAssignedToMe {
            Button(action: onToggleAssignedToMe) {
                Label(L10n.me, systemImage: isAssigneeHovering ? "xmark.circle.fill" : "person.fill")
                    .font(.caption)
                    .foregroundStyle(isAssigneeHovering ? .secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isAssigneeHovering = hovering
            }
            .accessibilityLabel(assigneeActionLabel)
        } else if !trimmedAssignee.isEmpty {
            Label(trimmedAssignee, systemImage: "person")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button(assigneeActionLabel, systemImage: "person.badge.plus") {
                onToggleAssignedToMe()
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
            .foregroundStyle(Color.secondary.opacity(0.6))
            .accessibilityLabel(assigneeActionLabel)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(completionLabel, systemImage: isCompleted ? "checkmark.circle.fill" : "circle") {
                onToggleCompleted()
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
            .foregroundStyle(isCompleted ? .green : .secondary)
            .accessibilityLabel(completionLabel)

            HStack(alignment: .top, spacing: 10) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                assigneeLabel

                Button(L10n.delete, systemImage: "trash") {
                    onDelete()
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(L10n.delete)
            }
        }
    }
}

struct MeetingActionItemRow: View {
    let actionItem: ActionItemRecord
    @ObservedObject var viewModel: CaptionViewModel

    var body: some View {
        ActionItemRowContent(
            title: actionItem.title,
            assignee: actionItem.assignee,
            isCompleted: actionItem.isCompleted,
            isExplicitlyAssignedToMe: actionItem.isExplicitlyAssignedToMe,
            onToggleCompleted: { viewModel.toggleActionItemCompletion(actionItem) },
            onToggleAssignedToMe: { viewModel.toggleActionItemAssignedToMe(actionItem) },
            onDelete: { viewModel.deleteActionItem(actionItem) }
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
