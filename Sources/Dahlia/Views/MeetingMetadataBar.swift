import SwiftUI

/// ミーティング詳細ヘッダーの下に配置するメタデータバー。
/// タグチップ群 + プロジェクトピッカーを横並びで表示する。
struct MeetingMetadataBar: View {
    let meeting: MeetingRecord
    let tags: [TagInfo]
    var sidebarViewModel: SidebarViewModel

    var body: some View {
        HStack(spacing: 8) {
            MeetingProjectPicker(meeting: meeting, sidebarViewModel: sidebarViewModel)
            MeetingTagsView(meetingId: meeting.id, tags: tags, sidebarViewModel: sidebarViewModel)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tag Management

private struct MeetingTagsView: View {
    let meetingId: UUID
    let tags: [TagInfo]
    var sidebarViewModel: SidebarViewModel

    @State private var showTagPopover = false
    @State private var tagInput = ""

    private var trimmedTagInput: String {
        tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [TagInfo] {
        let existingNames = Set(tags.map(\.name))
        let availableTags = sidebarViewModel.allAvailableTags.filter { !existingNames.contains($0.name) }
        guard !trimmedTagInput.isEmpty else { return availableTags }
        let query = trimmedTagInput.localizedLowercase
        return availableTags.filter { $0.name.localizedLowercase.contains(query) }
    }

    private var shouldShowCreateSuggestion: Bool {
        !trimmedTagInput.isEmpty
            && !tags.contains(where: { $0.name.caseInsensitiveCompare(trimmedTagInput) == .orderedSame })
            && !suggestions.contains(where: { $0.name.caseInsensitiveCompare(trimmedTagInput) == .orderedSame })
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.name) { tag in
                TagChip(tag: tag) {
                    sidebarViewModel.removeTagFromMeeting(id: meetingId, tag: tag.name)
                }
            }

            addTagButton
        }
    }

    private var addTagButton: some View {
        Button {
            tagInput = ""
            showTagPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.caption2)
                Text(L10n.addTag)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
            tagPopoverContent
        }
    }

    private var tagPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(L10n.searchOrCreateTag, text: $tagInput)
                .textFieldStyle(.plain)
                .padding(10)
                .onSubmit {
                    submitTagInput()
                }

            Divider()

            if !suggestions.isEmpty || !tagInput.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.name) { tag in
                            tagSuggestionRow(name: tag.name, colorHex: tag.colorHex, isNew: false)
                        }

                        if shouldShowCreateSuggestion {
                            tagSuggestionRow(name: trimmedTagInput, colorHex: nil, isNew: true)
                        }
                    }
                }
                .frame(maxHeight: 240)
            } else {
                // 既存タグが無くて入力もない場合
                VStack {
                    Spacer()
                    Text(L10n.noResultsFound)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
            }
        }
        .frame(width: 240)
    }

    private func tagSuggestionRow(name: String, colorHex: String?, isNew: Bool) -> some View {
        Button {
            sidebarViewModel.addTagToMeeting(id: meetingId, tag: name)
            tagInput = ""
        } label: {
            HStack(spacing: 6) {
                if isNew {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Circle()
                        .fill(Color(hex: colorHex ?? "#808080"))
                        .frame(width: 8, height: 8)
                }
                Text(name)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }

    private func submitTagInput() {
        guard !trimmedTagInput.isEmpty else { return }
        sidebarViewModel.addTagToMeeting(id: meetingId, tag: trimmedTagInput.localizedLowercase)
        tagInput = ""
    }
}

// MARK: - Tag Chip

private struct TagChip: View {
    let tag: TagInfo
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .opacity(isHovered ? 0 : 1)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .accessibilityLabel(L10n.delete)
            }
            .frame(width: 10, height: 10)

            Text(tag.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(hex: tag.colorHex).opacity(0.12))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Project Picker

private struct MeetingProjectPicker: View {
    let meeting: MeetingRecord
    var sidebarViewModel: SidebarViewModel

    @State private var showProjectPopover = false
    @State private var projectInput = ""
    @FocusState private var isProjectFieldFocused: Bool

    private var trimmedProjectInput: String {
        projectInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentProjectName: String {
        sidebarViewModel.flatProjects.first(where: { $0.id == meeting.projectId })?.name ?? ""
    }

    private var filteredProjects: [FlatProjectRow] {
        guard !trimmedProjectInput.isEmpty else { return sidebarViewModel.flatProjects }
        let query = trimmedProjectInput.localizedLowercase
        return sidebarViewModel.flatProjects.filter { project in
            project.name.localizedLowercase.contains(query) || project.displayName.localizedLowercase.contains(query)
        }
    }

    private var shouldShowCreateSuggestion: Bool {
        !trimmedProjectInput.isEmpty
            && !filteredProjects.contains(where: {
                $0.name.caseInsensitiveCompare(trimmedProjectInput) == .orderedSame
            })
    }

    private var emptyProjectMessage: String {
        sidebarViewModel.flatProjects.isEmpty && trimmedProjectInput.isEmpty ? L10n.noProjectsYet : L10n.noResultsFound
    }

    var body: some View {
        Button {
            projectInput = ""
            showProjectPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption2)
                Text(currentProjectName)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showProjectPopover, arrowEdge: .bottom) {
            projectPopoverContent
        }
    }

    private var projectPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(L10n.searchOrCreateProject, text: $projectInput)
                .textFieldStyle(.plain)
                .padding(10)
                .focused($isProjectFieldFocused)
                .onSubmit {
                    submitProjectInput()
                }

            Divider()

            if !filteredProjects.isEmpty || shouldShowCreateSuggestion {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredProjects, id: \.id) { project in
                            popoverRow(
                                icon: "folder",
                                name: project.name,
                                isSelected: project.id == meeting.projectId,
                            ) {
                                assignMeeting(to: project.id, projectName: project.name)
                            }
                        }

                        if shouldShowCreateSuggestion {
                            popoverRow(icon: "plus", name: trimmedProjectInput) {
                                createAndAssignProject(named: trimmedProjectInput)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            } else {
                VStack {
                    Spacer()
                    Text(emptyProjectMessage)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
        .frame(width: 280)
        .onAppear {
            isProjectFieldFocused = true
        }
    }

    private func popoverRow(
        icon: String,
        name: String,
        isSelected: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }

    private func submitProjectInput() {
        guard !trimmedProjectInput.isEmpty else { return }

        if let matchingProject = sidebarViewModel.flatProjects.first(where: {
            $0.name.caseInsensitiveCompare(trimmedProjectInput) == .orderedSame
        }) {
            assignMeeting(to: matchingProject.id, projectName: matchingProject.name)
            return
        }

        createAndAssignProject(named: trimmedProjectInput)
    }

    private func createAndAssignProject(named name: String) {
        guard let project = sidebarViewModel.fetchOrCreateProject(name: name) else { return }
        assignMeeting(to: project.record.id, projectName: project.record.name)
    }

    private func assignMeeting(to projectId: UUID, projectName: String) {
        if projectId != meeting.projectId {
            sidebarViewModel.moveMeeting(id: meeting.id, toProjectId: projectId)
        }
        sidebarViewModel.selectProject(id: projectId, name: projectName)
        sidebarViewModel.selectedMeetingId = meeting.id
        projectInput = ""
        showProjectPopover = false
    }
}

// MARK: - Flow Layout

/// タグチップを自動折り返しするレイアウト。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? .infinity, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified,
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return LayoutResult(positions: positions, size: CGSize(width: maxX, height: y + rowHeight))
    }
}
