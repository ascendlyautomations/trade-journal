import Foundation

/// Observable authentication state machine surface.
nonisolated enum AuthenticationState: Sendable, Equatable {
    /// Cold launch — restoration not finished.
    case unknown
    case unauthenticated
    case authenticating(AuthenticationProviderKind)
    case authenticated(AuthenticationSession)
    /// Access token expired/near expiry — refresh in flight. Not a usable session.
    case refreshing(AuthenticationSession)
    /// Refresh failed transiently — session remains in Keychain; user may retry.
    case sessionValidationFailed(AuthenticationSession, AuthenticationError)
    case locked(AuthenticationSession)
    case failure(AuthenticationError)

    /// True only when the user may enter the authenticated shell with a usable access token.
    var isSessionReady: Bool {
        switch self {
        case .authenticated, .locked:
            return true
        default:
            return false
        }
    }

    /// Legacy alias — prefer ``isSessionReady`` for shell gating.
    var isAuthenticated: Bool { isSessionReady }

    var isRestoringSession: Bool {
        switch self {
        case .unknown, .refreshing:
            return true
        default:
            return false
        }
    }

    var session: AuthenticationSession? {
        switch self {
        case .authenticated(let session), .refreshing(let session), .locked(let session),
             .sessionValidationFailed(let session, _):
            return session
        default:
            return nil
        }
    }
}
