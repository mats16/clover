import SwiftUI

/// Notion 風の最前面フローティングバナー。横一列にアイコン・テキスト・ボタンを配置。
struct MeetingDetectionPopupView: View {
    let meeting: DetectedMeeting
    let onOpen: () -> Void
    let onStart: () -> Void
    let onManageNotifications: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var isOptionsPresented = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: { closeAndPerform(onOpen) }) {
                HStack(spacing: 14) {
                    appIcon
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(meeting.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(L10n.meetingDetected)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)

            splitActionButton

            Button(L10n.dismiss, systemImage: "xmark", action: { closeAndPerform(onDismiss) })
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .glassEffect(isHovered ? .regular.interactive() : .clear, in: Circle())
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .pointerStyle(.link)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var splitActionButton: some View {
        HStack(spacing: 0) {
            Button(action: { closeAndPerform(onStart) }) {
                Text(L10n.startTranscribing)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 128)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 22)

            Button {
                isOptionsPresented.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .popover(
                isPresented: $isOptionsPresented,
                attachmentAnchor: .point(UnitPoint(x: 0.78, y: 1)),
                arrowEdge: .top
            ) {
                notificationOptionsMenu
            }
        }
        .background(Capsule().fill(Color.accentColor))
        .clipShape(Capsule())
    }

    private var notificationOptionsMenu: some View {
        Button(action: { closeAndPerform(onManageNotifications) }) {
            Label(L10n.manageNotificationSettings, systemImage: "bell")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 250, alignment: .leading)
    }

    private func closeAndPerform(_ action: () -> Void) {
        isOptionsPresented = false
        action()
    }
}
