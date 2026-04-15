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
    let meeting: MeetingRecord

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // アバター風サークルアイコン
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 40, height: 40)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, isActive: meeting.isRecording)
            }

            // タイトル + サブテキスト
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 日付（右寄せ）
            Text(relativeDate)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var displayTitle: String {
        if !meeting.name.isEmpty {
            return meeting.name
        }
        return L10n.newMeeting
    }

    private var displaySubtitle: String? {
        if meeting.isRecording {
            return "録音中"
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
        // ミーティング名のハッシュから色を決定
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
}
