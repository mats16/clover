import SwiftUI

/// プロジェクト選択時にメインエリアに表示するミーティング一覧。
struct MeetingListView: View {
    @ObservedObject var viewModel: CaptionViewModel
    var sidebarViewModel: SidebarViewModel
    var onSelectMeeting: (UUID) -> Void

    @State private var editingMeetingId: UUID?
    @State private var editingMeetingName = ""
    @FocusState private var isMeetingRenameFocused: Bool

    private var meetings: [MeetingRecord] {
        sidebarViewModel.meetingsForSelectedProject
    }

    private func isMeetingActive(_ id: UUID) -> Bool {
        if sidebarViewModel.selectedMeetingIds.count > 1 {
            return sidebarViewModel.selectedMeetingIds.contains(id)
        }
        return sidebarViewModel.selectedMeetingId == id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { sidebarViewModel.deselectProject() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.projects)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if let project = sidebarViewModel.selectedProject {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: createNewMeeting) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L10n.newTranscription)
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            Group {
                if meetings.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.newTranscription, systemImage: "waveform")
                    } description: {
                        Text(L10n.newTranscription)
                    } actions: {
                        Button(L10n.newTranscription, action: createNewMeeting)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(meetings, id: \.id) { meeting in
                                meetingRow(meeting)
                                if meeting.id != meetings.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
        .onDeleteCommand {
            let ids = sidebarViewModel.effectiveSelectedIds
            guard !ids.isEmpty else { return }
            if ids.count == 1, let single = ids.first {
                sidebarViewModel.deleteMeeting(id: single)
            } else {
                sidebarViewModel.deleteMeetings(ids: ids)
            }
        }
    }

    // MARK: - Meeting Row

    @ViewBuilder
    private func meetingRow(_ meeting: MeetingRecord) -> some View {
        if editingMeetingId == meeting.id {
            meetingRenameField(meeting.id)
        } else {
            Button {
                handleMeetingRowActivation(meeting)
            } label: {
                MeetingListRow(
                    meeting: meeting
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isMeetingActive(meeting.id) ? Color.primary.opacity(0.06) : Color.clear)
            )
            .draggable(draggablePayload(for: meeting.id))
            .contextMenu {
                meetingContextMenu(meeting)
            }
            .accessibilityLabel(meetingAccessibilityLabel(for: meeting))
        }
    }

    private func meetingRenameField(_ meetingId: UUID) -> some View {
        TextField(L10n.title, text: $editingMeetingName)
            .textFieldStyle(.roundedBorder)
            .focused($isMeetingRenameFocused)
            .onSubmit { commitMeetingRename(id: meetingId) }
            .onExitCommand { editingMeetingId = nil }
            .onChange(of: isMeetingRenameFocused) { _, focused in
                if !focused { commitMeetingRename(id: meetingId) }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                isMeetingRenameFocused = true
            }
    }

    @ViewBuilder
    private func meetingContextMenu(_ meeting: MeetingRecord) -> some View {
        let effectiveIds = sidebarViewModel.effectiveSelectedIds
        let isMulti = effectiveIds.count > 1 && effectiveIds.contains(meeting.id)

        if isMulti {
            Button(L10n.deleteCount(effectiveIds.count), role: .destructive) {
                sidebarViewModel.deleteMeetings(ids: effectiveIds)
            }
        } else {
            Button(L10n.rename) {
                editingMeetingName = meeting.name
                editingMeetingId = meeting.id
            }
            Divider()
            Button(L10n.delete, role: .destructive) {
                sidebarViewModel.deleteMeeting(id: meeting.id)
            }
        }
    }

    // MARK: - Actions

    private func handleMeetingRowActivation(_ meeting: MeetingRecord) {
        guard let project = sidebarViewModel.selectedProject else { return }
        let id = meeting.id
        let flags = NSEvent.modifierFlags

        if flags.contains(.command) {
            sidebarViewModel.toggleMeetingSelection(id, projectId: project.id, projectName: project.name)
        } else if flags.contains(.shift) {
            sidebarViewModel.rangeSelectMeeting(id, projectId: project.id, projectName: project.name)
        } else {
            sidebarViewModel.singleSelectMeeting(id, projectId: project.id, projectName: project.name)
            onSelectMeeting(id)
        }
    }

    private func commitMeetingRename(id: UUID) {
        guard editingMeetingId == id else { return }
        let trimmed = editingMeetingName.trimmingCharacters(in: .whitespaces)
        sidebarViewModel.renameMeeting(id: id, newName: trimmed)
        editingMeetingId = nil
    }

    private func draggablePayload(for id: UUID) -> String {
        let ids = sidebarViewModel.effectiveSelectedIds
        if ids.contains(id), ids.count > 1 {
            return ids.map(\.uuidString).joined(separator: "\n")
        }
        return id.uuidString
    }

    private func meetingAccessibilityLabel(for meeting: MeetingRecord) -> String {
        if meeting.name.isEmpty {
            return L10n.newMeeting
        }
        return meeting.name
    }

    private func createNewMeeting() {
        guard let project = sidebarViewModel.selectedProject,
              let dbQueue = sidebarViewModel.dbQueue,
              let projectURL = sidebarViewModel.selectedProjectURL,
              let vault = sidebarViewModel.currentVault
        else { return }

        viewModel.createEmptyMeeting(
            dbQueue: dbQueue,
            projectURL: projectURL,
            vaultId: vault.id,
            projectId: project.id,
            projectName: project.name,
            vaultURL: vault.url
        )

        if let newId = viewModel.currentMeetingId {
            sidebarViewModel.selectMeeting(newId)
            onSelectMeeting(newId)
        }
    }
}

// MARK: - Meeting List Row

/// Circleback 風ミーティング一覧行。
struct MeetingListRow: View {
    enum LayoutStyle {
        case regular
        case compact
    }

    let meeting: MeetingRecord
    var tags: [TagInfo] = []
    var style: LayoutStyle = .regular
    var showAvatar = true
    var showsSubtitle = true

    private static let maxVisibleTags = 2

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: metrics.horizontalSpacing) {
            avatar

            VStack(alignment: .leading, spacing: metrics.verticalSpacing) {
                HStack(alignment: .center, spacing: 8) {
                    Text(displayTitle)
                        .font(metrics.titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !visibleTags.isEmpty || overflowTagCount > 0 {
                        HStack(spacing: 5) {
                            ForEach(visibleTags, id: \.name) { tag in
                                MeetingListTagChip(tag: tag)
                            }

                            if overflowTagCount > 0 {
                                MeetingListOverflowChip(count: overflowTagCount)
                            }
                        }
                        .lineLimit(1)
                    }
                }

                if showsSubtitle, let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(metrics.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(relativeDate)
                .font(metrics.dateFont)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, metrics.verticalPadding)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(avatarGradient)
                .frame(width: metrics.avatarSize, height: metrics.avatarSize)
            Image(systemName: "waveform")
                .font(.system(size: metrics.iconSize, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating, isActive: meeting.isRecording)
        }
        .opacity(showAvatar ? 1 : 0)
    }

    private var displayTitle: String {
        if !meeting.name.isEmpty {
            return meeting.name
        }
        return L10n.newMeeting
    }

    private var displaySubtitle: String? {
        if meeting.isRecording {
            return L10n.recordingNow
        }
        if let duration = meeting.duration {
            let minutes = Int(duration / 60)
            return minutes > 0 ? "\(minutes)分" : "1分未満"
        }
        return nil
    }

    private var relativeDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(meeting.createdAt) {
            return "今日"
        } else if calendar.isDateInYesterday(meeting.createdAt) {
            return "昨日"
        }
        return Self.dayFormatter.string(from: meeting.createdAt)
    }

    private var avatarGradient: LinearGradient {
        if meeting.isRecording {
            return LinearGradient(
                colors: [.red, .red.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        let colors: [(Color, Color)] = [
            (.blue, .cyan),
            (.purple, .pink),
            (.orange, .yellow),
            (.green, .mint),
            (.indigo, .purple),
            (.teal, .green),
        ]
        let hash = abs(meeting.id.hashValue)
        let pair = colors[hash % colors.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var visibleTags: ArraySlice<TagInfo> {
        tags.prefix(Self.maxVisibleTags)
    }

    private var overflowTagCount: Int {
        max(0, tags.count - visibleTags.count)
    }

    private var metrics: LayoutMetrics { .forStyle(style) }

    private struct LayoutMetrics {
        let avatarSize: CGFloat
        let iconSize: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let verticalPadding: CGFloat
        let titleFont: Font
        let subtitleFont: Font
        let dateFont: Font

        static func forStyle(_ style: LayoutStyle) -> LayoutMetrics {
            switch style {
            case .regular:
                LayoutMetrics(
                    avatarSize: 40, iconSize: 14,
                    horizontalSpacing: 12, verticalSpacing: 3, verticalPadding: 8,
                    titleFont: .body.weight(.medium),
                    subtitleFont: .subheadline, dateFont: .subheadline
                )
            case .compact:
                LayoutMetrics(
                    avatarSize: 32, iconSize: 12,
                    horizontalSpacing: 10, verticalSpacing: 2, verticalPadding: 6,
                    titleFont: .subheadline.weight(.medium),
                    subtitleFont: .caption, dateFont: .caption
                )
            }
        }
    }
}

private struct MeetingListTagChip: View {
    let tag: TagInfo

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 6, height: 6)

            Text(tag.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(hex: tag.colorHex).opacity(0.12))
        )
    }
}

private struct MeetingListOverflowChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.05))
            )
    }
}
