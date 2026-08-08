import Foundation

/// Observable authentication state machine surface.
nonisolated enum AuthenticationState: Sendable, Equatable {
    /// Cold launch — restoration not finished.
    case unknown
    case unauthenticated
    case authenticating(AuthenticationProviderKind)
    case authenticated(AuthenticationSession)
    case refreshing(AuthenticationSession)
    case locked(AuthenticationSession)
    case failure(AuthenticationError)

    var isAuthenticated: Bool {
        switch self {
        case .authenticated, .refreshing, .locked:
            return true
        default:
            return false
        }
    }

    var session: AuthenticationSession? {
        switch self {
        case .authenticated(let session), .refreshing(let session), .locked(let session):
            return session
        default:
            return nil
        }
    }
}
