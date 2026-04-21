import Foundation

/// Agent CLI の permission mode。
enum AgentPermissionMode: String, CaseIterable, Identifiable {
    case auto
    case `default`
    case acceptEdits
    case bypassPermissions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            L10n.agentPermissionModeAuto
        case .default:
            L10n.agentPermissionModeDefault
        case .acceptEdits:
            L10n.agentPermissionModeAcceptEdits
        case .bypassPermissions:
            L10n.agentPermissionModeBypassPermissions
        }
    }
}
