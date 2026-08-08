import Foundation

nonisolated enum AuthenticationEvent: Sendable, Equatable {
    case restorationStarted
    case restorationSucceeded(userID: UserID)
    case restorationFailed
    case signInStarted(AuthenticationProviderKind)
    case signInSucceeded(userID: UserID, provider: AuthenticationProviderKind)
    case signInFailed(AuthenticationError)
    case tokenRefreshStarted
    case tokenRefreshSucceeded
    case tokenRefreshFailed
    case sessionExpired
    case logoutStarted
    case logoutCompleted
    case biometricUnlockSucceeded
    case biometricUnlockFailed
}
