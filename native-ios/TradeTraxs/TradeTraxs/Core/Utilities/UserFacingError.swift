import Foundation

/// Presentation-ready error copy. Views never show raw ``AppError`` strings.
nonisolated struct UserFacingError: Sendable, Equatable {
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
                message: sanitizeTechnicalMessage(message),
                action: .retry
            )
        }
    }

    /// Maps any thrown error into presentation copy (Settings / forms / soft failures).
    static func message(for error: Error) -> String {
        if let app = error as? AppError {
            return map(app).message
        }
        if let network = error as? NetworkError {
            return map(network).message
        }
        if let auth = error as? AuthenticationError {
            return map(auth).message
        }
        return map(AppError.unknown(message: error.localizedDescription)).message
    }

    /// Strips Swift dumps, PostgREST bodies, and transport prefixes from unknown paths.
    private static func sanitizeTechnicalMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Please try again."
        }
        let lowered = trimmed.lowercased()
        if trimmed.hasPrefix("Transport:")
            || trimmed.hasPrefix("Authentication:")
            || trimmed.hasPrefix("Not implemented:")
            || trimmed.hasPrefix("{")
            || trimmed.hasPrefix("[")
            || lowered.contains("pgrst")
            || lowered.hasPrefix("permission(")
            || lowered.hasPrefix("notfound(")
            || lowered.hasPrefix("businessrule(")
            || lowered.hasPrefix("subscription(")
            || lowered.hasPrefix("tradevalidation(")
            || lowered.hasPrefix("importfailure(")
            || lowered.hasPrefix("conflict(")
        {
            return "Please try again."
        }
        return trimmed
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
        case .providerMisconfigured(_):
            return UserFacingError(
                title: "Sign in unavailable",
                message: "Apple sign-in is not configured yet. Try email sign-in or contact support.",
                action: .dismiss
            )
        case .providerTokenInvalid(_):
            return UserFacingError(
                title: "Sign in failed",
                message: "Apple could not verify your account. Please try again.",
                action: .retry
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
                message: sanitizeTechnicalMessage(message ?? "Something went wrong on our end."),
                action: .retry
            )
        case .decoding:
            return UserFacingError(
                title: "Unexpected response",
                message: "We couldn't read the server response.",
                action: .retry
            )
        case .validation(_, let message):
            let lowered = message.lowercased()
            if lowered.contains("base url") || lowered.contains("not configured") {
                return UserFacingError(
                    title: "Unavailable",
                    message: "Trade AI isn’t available in this build. Please try again later.",
                    action: .dismiss
                )
            }
            return UserFacingError(
                title: "Invalid request",
                message: sanitizeTechnicalMessage(message),
                action: .dismiss
            )
        case .unknown(let message):
            return UserFacingError(
                title: "Something went wrong",
                message: sanitizeTechnicalMessage(message),
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
