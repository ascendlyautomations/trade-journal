import Foundation

/// Typed authentication failures — never wraps transport SDK strings for UI.
nonisolated enum AuthenticationError: Error, Sendable, Equatable {
    case notConfigured
    case invalidCredentials
    /// Sign-up rejected because the email is already registered (GoTrue — not a password sign-in failure).
    case emailAlreadyRegistered
    case invalidEmail
    case invalidPassword
    case sessionExpired
    case sessionMissing
    case emailConfirmationRequired(email: String)
    case refreshFailed
    case providerUnavailable(AuthenticationProviderKind)
    case providerMisconfigured(AuthenticationProviderKind)
    case providerTokenInvalid(AuthenticationProviderKind)
    case cancelled
    case biometricUnavailable
    case biometricFailed
    case keychain(String)
    case validation(String)
    case unknown(String)
}

extension AppError {
    static func from(_ error: AuthenticationError) -> AppError {
        switch error {
        case .cancelled:
            return .cancelled
        default:
            return .authentication(error)
        }
    }
}
