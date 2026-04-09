import SwiftUI

/// Notion 風の最前面フローティングバナー。横一列にアイコン・テキスト・ボタンを配置。
struct MeetingDetectionPopupView: View {
    let meeting: DetectedMeeting
    let onStart: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            appIcon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.startTranscription)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(meetingDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onStart) {
                Text(L10n.startTranscription)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.1 : 0)))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .pointerStyle(.link)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
    }

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var meetingDescription: String {
        meeting.appName.isEmpty
            ? L10n.microphoneInUse
            : L10n.meetingDetectedSubtitle(meeting.appName)
    }
}
