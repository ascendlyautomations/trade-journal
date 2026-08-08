import Foundation

/// Presentation-ready error copy. Views never show raw ``AppError`` strings.
struct UserFacingError: Sendable, Equatable {
    let title: String
    let message: String
    let action: Action?

    enum Action: Sendable, Equatable {
        case dismiss
        case retry
        /// Future: deep-link / navigation destinations.
        case custom(identifier: String)
    }

    /// Minimal mapping for foundation. Replace with richer copy tables later.
    static func map(_ error: AppError) -> UserFacingError {
        switch error {
        case .notImplemented(let feature):
            return UserFacingError(
                title: "Unavailable",
                message: "\(feature) is not available yet.",
                action: .dismiss
            )
        case .cancelled:
            return UserFacingError(
                title: "Cancelled",
                message: "The operation was cancelled.",
                action: .dismiss
            )
        case .transport(let networkError):
            return map(networkError)
        case .authentication(let authError):
            return map(authError)
        case .unknown(let message):
            return UserFacingError(
                title: "Something went wrong",
                message: message,
                action: .retry
            )
        }
    }

    static func map(_ error: AuthenticationError) -> UserFacingError {
        switch error {
        case .invalidCredentials, .invalidEmail, .invalidPassword:
            return UserFacingError(
                title: "Sign in failed",
                message: "Check your email and password and try again.",
                action: .retry
            )
        case .sessionExpired, .sessionMissing:
            return UserFacingError(
                title: "Signed out",
                message: "Please sign in again to continue.",
                action: .custom(identifier: "auth.reauthenticate")
            )
        case .notConfigured, .providerUnavailable:
            return UserFacingError(
                title: "Unavailable",
                message: "This sign-in method is not available yet.",
                action: .dismiss
            )
        case .cancelled:
            return UserFacingError(
                title: "Cancelled",
                message: "The operation was cancelled.",
                action: .dismiss
            )
        default:
            return UserFacingError(
                title: "Authentication error",
                message: "Something went wrong while signing in.",
                action: .retry
            )
        }
    }

    static func map(_ error: NetworkError) -> UserFacingError {
        switch error {
        case .connectivity:
            return UserFacingError(
                title: "You're offline",
                message: "Check your connection and try again.",
                action: .retry
            )
        case .timeout:
            return UserFacingError(
                title: "Request timed out",
                message: "The server took too long to respond.",
                action: .retry
            )
        case .cancelled:
            return UserFacingError(
                title: "Cancelled",
                message: "The operation was cancelled.",
                action: .dismiss
            )
        case .unauthorized:
            return UserFacingError(
                title: "Signed out",
                message: "Please sign in again to continue.",
                action: .custom(identifier: "auth.reauthenticate")
            )
        case .forbidden:
            return UserFacingError(
                title: "Not allowed",
                message: "You don't have permission to do that.",
                action: .dismiss
            )
        case .rateLimited:
            return UserFacingError(
                title: "Slow down",
                message: "Too many requests. Please wait a moment.",
                action: .retry
            )
        case .server(_, let message):
            return UserFacingError(
                title: "Server error",
                message: message ?? "Something went wrong on our end.",
                action: .retry
            )
        case .decoding:
            return UserFacingError(
                title: "Unexpected response",
                message: "We couldn't read the server response.",
                action: .retry
            )
        case .validation(let message):
            return UserFacingError(
                title: "Invalid request",
                message: message,
                action: .dismiss
            )
        case .unknown(let message):
            return UserFacingError(
                title: "Something went wrong",
                message: message,
                action: .retry
            )
        }
    }
}

extension FeedbackState {
    /// Bridges networking failures into Experience System feedback.
    static func from(networkError: NetworkError) -> FeedbackState {
        switch networkError {
        case .connectivity:
            return .offline(message: "Check your connection and try again.")
        case .cancelled:
            return .idle
        case .unauthorized, .forbidden, .validation:
            return .failure(message: UserFacingError.map(networkError).message, retryable: false)
        default:
            return .failure(
                message: UserFacingError.map(networkError).message,
                retryable: networkError.isRetryable
            )
        }
    }
}
