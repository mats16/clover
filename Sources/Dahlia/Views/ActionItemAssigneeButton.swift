import SwiftUI

struct ActionItemAssigneeButton: View {
    let assignee: String
    let onSetAssignee: (String) -> Void

    @State private var draftAssignee = ""
    @State private var isEditorPresented = false
    @FocusState private var isFieldFocused: Bool

    private var trimmedAssignee: String {
        assignee.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isExplicitlyAssignedToMe: Bool {
        SummaryActionItem.isExplicitlyAssignedToMe(assignee)
    }

    var body: some View {
        Button(action: presentEditor) {
            if isExplicitlyAssignedToMe {
                Label(L10n.me, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            } else if !trimmedAssignee.isEmpty {
                Label(trimmedAssignee, systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(L10n.editAssignee, systemImage: "person.badge.plus")
                    .font(.caption)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.editAssignee)
        .popover(isPresented: $isEditorPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.editAssignee)
                    .font(.headline)

                TextField(L10n.assignee, text: $draftAssignee)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .focused($isFieldFocused)
                    .onSubmit {
                        applyDraftAssignee()
                    }

                HStack(spacing: 8) {
                    Button(L10n.assignToMe) {
                        updateAssignee(SummaryActionItem.selfAssigneeKey)
                    }

                    Spacer(minLength: 0)

                    Button(L10n.clear) {
                        updateAssignee("")
                    }

                    Button(L10n.apply) {
                        applyDraftAssignee()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private func presentEditor() {
        draftAssignee = trimmedAssignee
        isEditorPresented = true
        isFieldFocused = true
    }

    private func applyDraftAssignee() {
        updateAssignee(draftAssignee)
    }

    private func updateAssignee(_ value: String) {
        onSetAssignee(value)
        isEditorPresented = false
    }
}
