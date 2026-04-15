import SwiftUI

/// アプリ全体のトップレベルナビゲーションを表示するサイドバー。
struct SidebarView: View {
    @Bindable var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }
    var onStartNewMeeting: () -> Void = {}
    var isNewMeetingDisabled = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            NewMeetingButton(
                isDisabled: isNewMeetingDisabled,
                action: onStartNewMeeting
            )
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            sidebarNavigation

            Spacer(minLength: 0)

            Divider()
            sidebarFooter
        }
    }

    private var sidebarNavigation: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(SidebarDestination.allCases) { destination in
                    SidebarNavigationRow(
                        destination: destination,
                        isSelected: sidebarViewModel.selectedDestination == destination
                    ) {
                        sidebarViewModel.selectedDestination = destination
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 0) {
            VaultMenuButton(
                currentVault: sidebarViewModel.currentVault,
                allVaults: sidebarViewModel.allVaults,
                onSelectVault: onSelectVault,
                onManageVaults: { openWindow(id: WindowID.vaultManager) }
            )

            Spacer()

            Button(L10n.settings, systemImage: "gearshape") {
                openSettings()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
            .help(L10n.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// サイドバー最上部に表示する「New meeting」ボタン。
private struct NewMeetingButton: View {
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.newMeeting)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered && !isDisabled ? Color.primary.opacity(0.04) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .pointerStyle(.link)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(L10n.newMeeting)
    }
}

private struct SidebarNavigationRow: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(destination.title, systemImage: destination.systemImage)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.primary.opacity(0.06) : Color.clear)
        )
    }
}

/// 保管庫切り替えメニュー。
private struct VaultMenuButton: View {
    let currentVault: VaultRecord?
    let allVaults: [VaultRecord]
    let onSelectVault: (VaultRecord) -> Void
    let onManageVaults: () -> Void

    var body: some View {
        Menu {
            ForEach(allVaults) { vault in
                Button {
                    onSelectVault(vault)
                } label: {
                    if currentVault?.id == vault.id {
                        Label(vault.name, systemImage: "checkmark")
                    } else {
                        Text(vault.name)
                    }
                }
            }

            Divider()

            Button(L10n.manageVaults, action: onManageVaults)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(currentVault?.name ?? L10n.vault)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .help(L10n.switchVault)
    }
}
