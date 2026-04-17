import SwiftUI

struct ActionItemRowContent: View {
    let title: String
    let assignee: String
    let isCompleted: Bool
    let onToggleCompleted: () -> Void
    let onSetAssignee: (String) -> Void
    let onDelete: () -> Void

    private var completionLabel: String {
        isCompleted ? L10n.markActionItemIncomplete : L10n.markActionItemComplete
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

                ActionItemAssigneeButton(
                    assignee: assignee,
                    onSetAssignee: onSetAssignee
                )

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
            onToggleCompleted: { viewModel.toggleActionItemCompletion(actionItem) },
            onSetAssignee: { viewModel.setActionItemAssignee(actionItem, assignee: $0) },
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
