import SwiftUI

private enum InstructionsEditorLayout {
    static let editorPadding = EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
}

struct InstructionsWorkspaceView: View {
    var sidebarViewModel: SidebarViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var draftName = ""
    @State private var draftContent = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isNameFieldFocused: Bool

    private let listWidth: CGFloat = 280

    var body: some View {
        HStack(spacing: 0) {
            instructionsList
                .frame(width: listWidth)

            Divider()

            instructionEditor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        .onAppear(perform: syncDraftsFromSelection)
        .onChange(of: sidebarViewModel.selectedInstruction?.id) { _, _ in
            syncDraftsFromSelection()
        }
        .onChange(of: draftName) { _, _ in
            scheduleSave()
        }
        .onChange(of: draftContent) { _, _ in
            scheduleSave()
        }
        .onDisappear {
            saveTask?.cancel()
            persistDraftsIfNeeded()
        }
        .onDeleteCommand(perform: deleteSelectedInstruction)
    }

    private var instructionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.instructions)
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 0)

                Button(L10n.create, systemImage: "plus") {
                    createInstruction()
                }
                .labelStyle(.iconOnly)
                .help(L10n.addInstruction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if sidebarViewModel.allInstructions.isEmpty {
                ContentUnavailableView {
                    Label(L10n.noInstructionsYet, systemImage: SidebarDestination.instructions.systemImage)
                } description: {
                    Text(L10n.addInstructionDescription)
                } actions: {
                    Button(L10n.addInstruction, action: createInstruction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sidebarViewModel.allInstructions) { instruction in
                            Button {
                                sidebarViewModel.selectInstruction(instruction.id)
                            } label: {
                                instructionRow(instruction)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    sidebarViewModel.deleteInstruction(id: instruction.id)
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var instructionEditor: some View {
        if let selectedInstruction = sidebarViewModel.selectedInstruction {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(L10n.title, text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.largeTitle.weight(.semibold))
                            .focused($isNameFieldFocused)

                        Text(activeInstructionStatusText(for: selectedInstruction))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        if appSettings.selectedInstructionID == selectedInstruction.id {
                            Button(L10n.useAutoInstructions) {
                                sidebarViewModel.useInstructionForSummary(nil)
                            }
                        } else {
                            Button(L10n.useForSummary) {
                                sidebarViewModel.useInstructionForSummary(selectedInstruction.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(L10n.delete, role: .destructive) {
                            sidebarViewModel.deleteInstruction(id: selectedInstruction.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Divider()

                TextEditor(text: $draftContent)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(InstructionsEditorLayout.editorPadding)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(12)
            }
        } else if sidebarViewModel.allInstructions.isEmpty {
            ContentUnavailableView {
                Label(L10n.instructions, systemImage: SidebarDestination.instructions.systemImage)
            } description: {
                Text(L10n.addInstructionDescription)
            } actions: {
                Button(L10n.addInstruction, action: createInstruction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(L10n.instructions, systemImage: SidebarDestination.instructions.systemImage)
            } description: {
                Text(L10n.selectInstructionDescription)
            } actions: {
                if let firstInstruction = sidebarViewModel.allInstructions.first {
                    Button(L10n.selectInstruction) {
                        sidebarViewModel.selectInstruction(firstInstruction.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func instructionRow(_ instruction: InstructionRecord) -> some View {
        let isSelected = sidebarViewModel.selectedInstruction?.id == instruction.id

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(instruction.displayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if appSettings.selectedInstructionID == instruction.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(L10n.summaryInstructionSelected)
                    }
                }

                Text(preview(for: instruction.content))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        )
    }

    private func preview(for content: String) -> String {
        let compact = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? L10n.instructionsEmptyContent : compact
    }

    private func activeInstructionStatusText(for instruction: InstructionRecord) -> String {
        if appSettings.selectedInstructionID == instruction.id {
            return L10n.summaryInstructionSelected
        }
        return L10n.summaryInstructionNotSelected
    }

    private func syncDraftsFromSelection() {
        saveTask?.cancel()
        draftName = sidebarViewModel.selectedInstruction?.name ?? ""
        draftContent = sidebarViewModel.selectedInstruction?.content ?? ""
    }

    private func scheduleSave() {
        guard sidebarViewModel.selectedInstruction != nil else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            persistDraftsIfNeeded()
        }
    }

    private func persistDraftsIfNeeded() {
        guard let selectedInstruction = sidebarViewModel.selectedInstruction else { return }

        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            draftName = selectedInstruction.name
            return
        }

        guard trimmedName != selectedInstruction.name || draftContent != selectedInstruction.content else { return }
        sidebarViewModel.updateInstruction(id: selectedInstruction.id, name: trimmedName, content: draftContent)
    }

    private func createInstruction() {
        guard let instruction = sidebarViewModel.createInstruction() else { return }
        sidebarViewModel.selectInstruction(instruction.id)
        isNameFieldFocused = true
    }

    private func deleteSelectedInstruction() {
        guard let selectedInstruction = sidebarViewModel.selectedInstruction else { return }
        sidebarViewModel.deleteInstruction(id: selectedInstruction.id)
    }
}
