import Foundation

/// Classifies room message insert failures, membership (RLS member gate) vs channel permissions.
enum RoomMessageSendDiagnostics: Sendable {
    case membershipNotConfirmed
    case channelPostingRestricted
    case serverRejectedRLS
    case other

    nonisolated var logLabel: String {
        switch self {
        case .membershipNotConfirmed:
            return "membership_not_confirmed"
        case .channelPostingRestricted:
            return "channel_posting_restricted"
        case .serverRejectedRLS:
            return "server_rls_rejected"
        case .other:
            return "other"
        }
    }

  /// Best-effort classification using client state plus PostgREST body (no RLS bypass).
    nonisolated static func classify(
        error: Error,
        hasServerMembership: Bool,
        canPostInChannel: Bool,
        isOwner: Bool,
        viewerHasModeratorTag: Bool
    ) -> Self {
        if !hasServerMembership, !isOwner {
            return .membershipNotConfirmed
        }
        if !canPostInChannel, !isOwner, !viewerHasModeratorTag {
            return .channelPostingRestricted
        }
        let body = errorDescription(error).lowercased()
        if body.contains("row-level security")
            || body.contains("42501")
            || body.contains("rls")
        {
            return .serverRejectedRLS
        }
        return .other
    }

    nonisolated static func errorDescription(_ error: Error) -> String {
        if let app = error as? AppError, case .transport(let transport) = app {
            switch transport {
            case .validation(_, let message):
                return message
            case .server(_, let message):
                return message ?? String(describing: error)
            default:
                break
            }
        }
        return String(describing: error)
    }
}