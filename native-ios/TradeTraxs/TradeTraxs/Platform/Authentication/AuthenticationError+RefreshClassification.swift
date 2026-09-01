import Foundation

extension AuthenticationError {
    /// Failures that invalidate the persisted refresh session — user must sign in again.
    var isTerminalRefreshFailure: Bool {
        switch self {
        case .invalidCredentials, .refreshFailed, .sessionExpired, .sessionMissing:
            return true
        case .notConfigured, .invalidEmail, .invalidPassword, .providerUnavailable,
             .providerMisconfigured, .providerTokenInvalid,
             .cancelled, .biometricUnavailable, .biometricFailed, .keychain,
             .validation, .unknown:
            return false
        }
    }

    /// Failures where the refresh token may still be valid — show recoverable UI and retry.
    var isTransientRefreshFailure: Bool {
        if isTerminalRefreshFailure { return false }
        switch self {
        case .cancelled:
            return false
        default:
            return true
        }
    }

    /// Maps transport / wrapped errors encountered during token refresh.
    static func fromRefreshFailure(_ error: Error) -> AuthenticationError {
        if let auth = error as? AuthenticationError {
            return auth
        }
        if let app = error as? AppError {
            switch app {
            case .transport(let network):
                switch network {
                case .connectivity, .timeout:
                    return .unknown("networkUnavailable")
                case .server(let code, _) where (500...599).contains(code):
                    return .unknown("serverUnavailable")
                case .cancelled:
                    return .cancelled
                case .unauthorized, .forbidden:
                    return .refreshFailed
                case .server(let code, _) where code == 400 || code == 401:
                    return .refreshFailed
                default:
                    return .unknown("transport")
                }
            case .authentication(let auth):
                return auth
            case .cancelled:
                return .cancelled
            default:
                return .unknown(String(describing: app))
            }
        }
        if error is CancellationError {
            return .cancelled
        }
        return .unknown(error.localizedDescription)
    }
}
