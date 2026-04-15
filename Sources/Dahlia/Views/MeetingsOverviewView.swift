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

    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectMeeting: (UUID) -> Void

    @State private var filter: Filter = .all

    private var meetings: [MeetingOverviewItem] {
        let allMeetings = sidebarViewModel.allMeetings
        let calendar = Calendar.current

        switch filter {
        case .all:
            return allMeetings
        case .today:
            return allMeetings.filter { calendar.isDateInToday($0.createdAt) }
        case .inProgress:
            return allMeetings.filter { $0.status == .recording }
        }
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

                    HStack(spacing: 10) {
                        Button(action: resetFilter) {
                            Text(filter.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(L10n.newTranscription, systemImage: "plus", action: createNewMeeting)
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.05))
                            )
                            .buttonStyle(.plain)
                            .help(L10n.newTranscription)
                            .accessibilityLabel(L10n.newTranscription)
                    }

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

                if meetings.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.noMeetingsYet, systemImage: "calendar")
                    } description: {
                        Text(filter == .all ? L10n.newTranscription : L10n.noMeetingsMatchFilter)
                    } actions: {
                        if filter == .all {
                            Button(L10n.newTranscription, action: createNewMeeting)
                        } else {
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

    private func createNewMeeting() {
        guard let dbQueue = sidebarViewModel.dbQueue,
              let vault = sidebarViewModel.currentVault,
              let project = sidebarViewModel.fetchOrCreateProject(name: "Meetings")
        else { return }

        sidebarViewModel.selectProject(id: project.record.id, name: project.record.name)
        viewModel.createEmptyMeeting(
            dbQueue: dbQueue,
            projectURL: project.url,
            projectId: project.record.id,
            projectName: project.record.name,
            vaultURL: vault.url
        )

        if let newId = viewModel.currentMeetingId {
            sidebarViewModel.selectMeeting(newId)
            onSelectMeeting(newId)
        }
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
    private static let defaultProjectName = "Meetings"

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
        HStack(alignment: .center, spacing: 0) {
            Button(action: onToggleCheck) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.5))
                    .opacity(showControls ? 1 : 0)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .padding(.leading, 6)

            HStack(alignment: .center, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(displayTitle)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let badgeTitle {
                            Text(badgeTitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.05))
                                )
                        }
                    }

                    Text(displaySubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(relativeDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

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
        return item.projectName
    }

    private var badgeTitle: String? {
        guard item.projectName != Self.defaultProjectName else { return nil }
        return item.projectName.split(separator: "/").last.map(String.init) ?? item.projectName
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
        let pair = colors[abs(item.projectId.hashValue) % colors.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilityLabel: String {
        "\(displayTitle), \(displaySubtitle), \(relativeDate)"
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
