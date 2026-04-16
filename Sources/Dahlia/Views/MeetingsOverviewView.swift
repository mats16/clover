import AppKit
import SwiftUI

/// サイドバーの Meetings から開く全 meeting 一覧。
struct MeetingsOverviewView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case today
        case inProgress

        var id: Self { self }

        var title: String {
            switch self {
            case .all:
                L10n.all
            case .today:
                L10n.today
            case .inProgress:
                L10n.inProgress
            }
        }
    }

    var sidebarViewModel: SidebarViewModel
    var onSelectMeeting: (UUID) -> Void

    @State private var filter: Filter = .all
    @State private var appliedFilterSelection = MeetingOverviewFilterSelection()
    @State private var draftFilterSelection = MeetingOverviewFilterSelection()
    @State private var showFilterPopover = false

    private var hasActiveFilters: Bool {
        !appliedFilterSelection.isEmpty
    }

    private var hasAnyFilterApplied: Bool {
        filter != .all || hasActiveFilters
    }

    private var activeFilterChips: [FilterChipData] {
        var chips: [FilterChipData] = []
        for projectId in appliedFilterSelection.projectIds {
            if let project = availableProjects.first(where: { $0.id == projectId }) {
                chips.append(FilterChipData(kind: .project(projectId), label: project.name))
            }
        }
        for tag in availableTags.filter({ appliedFilterSelection.tagNames.contains($0.name) }) {
            chips.append(FilterChipData(kind: .tag(tag.name), label: tag.name, tagColorHex: tag.colorHex))
        }
        return chips
    }

    private func removeFilterChip(_ chip: FilterChipData) {
        switch chip.kind {
        case let .project(id):
            appliedFilterSelection.projectIds.remove(id)
            draftFilterSelection.projectIds.remove(id)
        case let .tag(name):
            appliedFilterSelection.tagNames.remove(name)
            draftFilterSelection.tagNames.remove(name)
        }
    }

    private var availableProjects: [MeetingOverviewProjectOption] {
        MeetingOverviewFilters.projectOptions(from: sidebarViewModel.allProjectItems)
    }

    private var availableTags: [TagInfo] {
        MeetingOverviewFilters.tagOptions(from: sidebarViewModel.allMeetings)
    }

    private var meetings: [MeetingOverviewItem] {
        var result = sidebarViewModel.allMeetings
        let calendar = Calendar.current

        switch filter {
        case .all:
            break
        case .today:
            result = result.filter { calendar.isDateInToday($0.createdAt) }
        case .inProgress:
            result = result.filter { $0.status == .recording }
        }

        return MeetingOverviewFilters.apply(selection: appliedFilterSelection, to: result)
    }

    private var isMultiSelectMode: Bool {
        !sidebarViewModel.selectedMeetingIds.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.meetings)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Button {
                            draftFilterSelection = appliedFilterSelection
                            showFilterPopover = true
                        } label: {
                            Label(L10n.filter, systemImage: "line.3.horizontal.decrease")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                            FilterDropdown(
                                selection: $draftFilterSelection,
                                availableProjects: availableProjects,
                                availableTags: availableTags,
                                onApply: {
                                    appliedFilterSelection = draftFilterSelection
                                    showFilterPopover = false
                                },
                                onReset: {
                                    draftFilterSelection = MeetingOverviewFilterSelection()
                                }
                            )
                        }

                        ForEach(activeFilterChips, id: \.id) { chip in
                            FilterChip(chip: chip) {
                                removeFilterChip(chip)
                            }
                        }
                    }
                }

                if meetings.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.noMeetingsYet, systemImage: "calendar")
                    } description: {
                        if hasAnyFilterApplied {
                            Text(L10n.noMeetingsMatchFilter)
                        }
                    } actions: {
                        if hasAnyFilterApplied {
                            Button(L10n.all, action: resetFilter)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(meetings) { item in
                            MeetingsOverviewRow(
                                item: item,
                                isSelected: sidebarViewModel.effectiveSelectedIds.contains(item.meetingId),
                                isMultiSelectMode: isMultiSelectMode,
                                isChecked: sidebarViewModel.selectedMeetingIds.contains(item.meetingId),
                                onSelect: { handleRowActivation(item) },
                                onToggleCheck: { toggleCheck(item) },
                                onDelete: { sidebarViewModel.deleteMeeting(id: item.meetingId) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, isMultiSelectMode ? 80 : 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .onDeleteCommand(perform: deleteSelection)
    }

    private func resetFilter() {
        filter = .all
        appliedFilterSelection = MeetingOverviewFilterSelection()
        draftFilterSelection = MeetingOverviewFilterSelection()
    }

    private func handleRowActivation(_ item: MeetingOverviewItem) {
        let flags = NSEvent.modifierFlags

        if isMultiSelectMode, !flags.contains(.command), !flags.contains(.shift) {
            // マルチ選択モード中の通常クリックはトグル
            sidebarViewModel.toggleMeetingSelection(
                item.meetingId,
                projectId: item.projectId,
                projectName: item.projectName
            )
        } else if flags.contains(.command) {
            sidebarViewModel.toggleMeetingSelection(
                item.meetingId,
                projectId: item.projectId,
                projectName: item.projectName
            )
        } else if flags.contains(.shift) {
            sidebarViewModel.rangeSelectMeeting(
                item.meetingId,
                projectId: item.projectId,
                projectName: item.projectName
            )
        } else {
            sidebarViewModel.singleSelectMeeting(
                item.meetingId,
                projectId: item.projectId,
                projectName: item.projectName
            )
            onSelectMeeting(item.meetingId)
        }
    }

    private func toggleCheck(_ item: MeetingOverviewItem) {
        sidebarViewModel.toggleMeetingSelection(
            item.meetingId,
            projectId: item.projectId,
            projectName: item.projectName
        )
    }

    private func deleteSelection() {
        let ids = sidebarViewModel.effectiveSelectedIds
        guard !ids.isEmpty else { return }

        if ids.count == 1, let id = ids.first {
            sidebarViewModel.deleteMeeting(id: id)
        } else {
            sidebarViewModel.deleteMeetings(ids: ids)
        }
    }
}

// MARK: - Meeting Row

private struct MeetingsOverviewRow: View {
    private static let maxVisibleTags = 2

    let item: MeetingOverviewItem
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var showControls: Bool {
        isMultiSelectMode || isHovering
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                avatar
                    .opacity(showControls ? 0 : 1)

                Button(action: onToggleCheck) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(showControls ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(displayTitle)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !metadataChips.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(metadataChips) { chip in
                                MeetingOverviewMetadataChip(chip: chip)
                            }
                        }
                        .lineLimit(1)
                    }
                }

                if let subtitleText {
                    Text(subtitleText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(relativeDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .trailing) {
            Menu {
                Button(L10n.delete, role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 12)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .background(backgroundStyle)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isMultiSelectMode)
        .contextMenu {
            Button(L10n.delete, role: .destructive, action: onDelete)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(avatarGradient)
                .frame(width: 38, height: 38)

            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .bottomTrailing) {
            if item.status == .recording {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(.background, lineWidth: 2)
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private var backgroundStyle: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(isHovering ? 0.04 : 0.0))
    }

    private var displayTitle: String {
        let trimmed = item.meetingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return L10n.newMeeting
    }

    private var displaySubtitle: String {
        if let preview = trimmedPreview, !preview.isEmpty {
            return preview
        }
        if item.status == .recording {
            return L10n.recordingNow
        }
        if item.segmentCount == 0 {
            return L10n.noConversationDetected
        }
        return item.projectName ?? L10n.noProject
    }

    private var subtitleText: String? {
        let subtitle = displaySubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subtitle.isEmpty else { return nil }
        guard subtitle != item.projectName || metadataChips.isEmpty else { return nil }
        return subtitle
    }

    private var metadataChips: [MeetingOverviewMetadataChipData] {
        var chips: [MeetingOverviewMetadataChipData] = []

        if let projectName = item.projectName, !projectName.isEmpty {
            chips.append(.project(projectName))
        }

        let visibleTags = item.tags.prefix(Self.maxVisibleTags)
        chips.append(contentsOf: visibleTags.map(MeetingOverviewMetadataChipData.tag))

        let overflowCount = item.tags.count - visibleTags.count
        if overflowCount > 0 {
            chips.append(.overflow(overflowCount))
        }

        return chips
    }

    private var relativeDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(item.createdAt) {
            return item.createdAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(item.createdAt) {
            return L10n.yesterday
        }
        return item.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var trimmedPreview: String? {
        let preview = item.latestSegmentText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview, !preview.isEmpty else { return nil }
        return preview
    }

    private var avatarGradient: LinearGradient {
        let colors: [(Color, Color)] = [
            (.blue, .cyan),
            (.orange, .yellow),
            (.teal, .mint),
            (.indigo, .purple),
            (.pink, .red),
            (.green, .teal),
        ]
        let seed = item.projectId?.hashValue ?? item.meetingId.hashValue
        let pair = colors[abs(seed) % colors.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilityLabel: String {
        [
            displayTitle,
            metadataAccessibilityLabel,
            subtitleText,
            relativeDate,
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
    }

    private var metadataAccessibilityLabel: String? {
        let labels = metadataChips.map(\.accessibilityLabel)
        guard !labels.isEmpty else { return nil }
        return labels.joined(separator: ", ")
    }
}

private struct MeetingOverviewMetadataChipData: Identifiable {
    enum Kind {
        case project
        case tag
        case overflow
    }

    let kind: Kind
    let label: String
    let dotColor: Color?
    let accessibilityLabel: String

    var id: String {
        switch kind {
        case .project:
            "project-\(label)"
        case .tag:
            "tag-\(label)"
        case .overflow:
            "overflow-\(label)"
        }
    }

    static func project(_ name: String) -> Self {
        .init(
            kind: .project,
            label: name,
            dotColor: nil,
            accessibilityLabel: "\(L10n.projects): \(name)"
        )
    }

    static func tag(_ tag: TagInfo) -> Self {
        .init(
            kind: .tag,
            label: tag.name,
            dotColor: Color(hex: tag.colorHex),
            accessibilityLabel: "\(L10n.tags): \(tag.name)"
        )
    }

    static func overflow(_ count: Int) -> Self {
        .init(
            kind: .overflow,
            label: "+\(count)",
            dotColor: nil,
            accessibilityLabel: "\(L10n.tags): +\(count)"
        )
    }
}

private struct MeetingOverviewMetadataChip: View {
    let chip: MeetingOverviewMetadataChipData

    var body: some View {
        HStack(spacing: 5) {
            switch chip.kind {
            case .project:
                Image(systemName: "folder")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            case .tag:
                Circle()
                    .fill(chip.dotColor ?? .secondary)
                    .frame(width: 7, height: 7)
            case .overflow:
                EmptyView()
            }

            Text(chip.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(chipBackgroundColor)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel)
    }

    private var chipBackgroundColor: Color {
        if case .tag = chip.kind {
            return (chip.dotColor ?? .secondary).opacity(0.12)
        }
        return Color.primary.opacity(0.05)
    }
}

// MARK: - Batch Selection Bar

struct BatchSelectionBar: View {
    let selectedCount: Int
    let onClearSelection: () -> Void
    let onDelete: () -> Void

    @State private var isClearHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.selectedCount(selectedCount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Button(action: onClearSelection) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.quaternary)
                                .opacity(isClearHovered ? 1 : 0)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.quaternary, lineWidth: 1)
                                .allowsHitTesting(false)
                                .opacity(isClearHovered ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isClearHovered = hovering
                }
            }
            .padding(.horizontal, 16)

            Button(action: onDelete) {
                Label(L10n.delete, systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isDeleteHovered ? .white : .red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(isDeleteHovered ? Color.red : Color.clear)
                    )
                    .overlay {
                        Capsule()
                            .stroke(isDeleteHovered ? Color.red : Color.primary.opacity(0.12), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(isDeleteHovered ? 0.18 : 0), radius: isDeleteHovered ? 10 : 0, y: isDeleteHovered ? 3 : 0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isDeleteHovered = hovering
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.background)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .allowsHitTesting(false)
        )
        .overlay(
            Capsule()
                .stroke(.quaternary, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}

// MARK: - Filter Chip

private struct FilterChipData: Identifiable {
    enum Kind: Hashable {
        case project(UUID)
        case tag(String)
    }

    let kind: Kind
    let label: String
    var tagColorHex: String?

    var id: String {
        switch kind {
        case let .project(id): "project-\(id)"
        case let .tag(tag): "tag-\(tag)"
        }
    }

    var prefix: String {
        switch kind {
        case .project: L10n.projectIs
        case .tag: L10n.tagIs
        }
    }

    var dotColor: Color {
        switch kind {
        case .project: .orange
        case .tag: Color(hex: tagColorHex ?? "#808080")
        }
    }
}

private struct FilterChip: View {
    let chip: FilterChipData
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(chip.prefix)
                .foregroundStyle(.secondary)

            Circle()
                .fill(chip.dotColor)
                .frame(width: 8, height: 8)

            Text(chip.label)
                .foregroundStyle(.primary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Filter Dropdown

private struct FilterDropdown: View {
    @Binding var selection: MeetingOverviewFilterSelection
    let availableProjects: [MeetingOverviewProjectOption]
    let availableTags: [TagInfo]
    let onApply: () -> Void
    let onReset: () -> Void

    @State private var expandedSection: Section?
    @State private var searchText = ""

    private enum Section: Hashable {
        case projects
        case tags
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expandedSection == nil {
                FilterDropdownRow(
                    title: L10n.projects,
                    systemImage: "folder",
                    badgeCount: selection.projectIds.count,
                    showChevron: true
                ) {
                    expandedSection = .projects
                    searchText = ""
                }

                Divider().padding(.horizontal, 8)

                FilterDropdownRow(
                    title: L10n.tags,
                    systemImage: "tag",
                    badgeCount: selection.tagNames.count,
                    showChevron: true
                ) {
                    expandedSection = .tags
                    searchText = ""
                }
            } else {
                FilterDropdownRow(
                    title: expandedSection == .projects ? L10n.projects : L10n.tags,
                    systemImage: "chevron.left",
                    badgeCount: 0,
                    showChevron: false
                ) {
                    expandedSection = nil
                    searchText = ""
                }

                Divider().padding(.horizontal, 8)

                TextField(L10n.searchFilters, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider().padding(.horizontal, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        switch expandedSection {
                        case .projects:
                            if filteredProjects.isEmpty {
                                FilterDropdownEmptyState()
                            } else {
                                ForEach(filteredProjects) { project in
                                    FilterDropdownItem(
                                        title: project.name,
                                        isSelected: selection.projectIds.contains(project.id)
                                    ) {
                                        toggleProject(project.id)
                                    }
                                }
                            }
                        case .tags:
                            if filteredTags.isEmpty {
                                FilterDropdownEmptyState()
                            } else {
                                ForEach(filteredTags, id: \.name) { tag in
                                    FilterDropdownItem(
                                        title: tag.name,
                                        isSelected: selection.tagNames.contains(tag.name),
                                        dotColor: Color(hex: tag.colorHex)
                                    ) {
                                        toggleTag(tag.name)
                                    }
                                }
                            }
                        case nil:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .defaultScrollAnchor(.top)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180, alignment: .top)
            }

            Divider().padding(.horizontal, 8)

            HStack(spacing: 12) {
                Button(L10n.clear, action: onReset)
                    .disabled(selection.isEmpty)

                Spacer()

                Button(L10n.apply, action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .padding(.vertical, 6)
        .frame(width: 260)
        .frame(maxHeight: 340)
    }

    private var filteredProjects: [MeetingOverviewProjectOption] {
        guard !searchText.isEmpty else { return availableProjects }
        return availableProjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredTags: [TagInfo] {
        guard !searchText.isEmpty else { return availableTags }
        return availableTags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func toggleProject(_ id: UUID) {
        var updated = selection
        updated.projectIds.toggle(id)
        selection = updated
    }

    private func toggleTag(_ name: String) {
        var updated = selection
        updated.tagNames.toggle(name)
        selection = updated
    }
}

private struct FilterDropdownRow: View {
    let title: String
    let systemImage: String
    let badgeCount: Int
    let showChevron: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}

private struct FilterDropdownItem: View {
    let title: String
    let isSelected: Bool
    var dotColor: Color?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? (dotColor ?? Color.accentColor) : (dotColor ?? Color.secondary).opacity(0.3))
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}

private struct FilterDropdownEmptyState: View {
    var body: some View {
        Text(L10n.noResultsFound)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
    }
}
