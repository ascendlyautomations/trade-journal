import Foundation

/// Typed application errors.
///
/// Domain and data layers produce ``AppError``; ViewModels map to ``UserFacingError``.
enum AppError: Error, Sendable, Equatable {
    /// Capability not wired yet (foundation placeholders).
    case notImplemented(feature: String)

    /// Cooperative cancellation (Task cancelled, user dismissed, etc.).
    case cancelled

    /// Networking / transport failures.
    case transport(NetworkError)

    /// Authentication / session failures.
    case authentication(AuthenticationError)

    /// Catch-all until richer typed errors exist.
    case unknown(message: String)
}

extension AppError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notImplemented(let feature):
            return "Not implemented: \(feature)"
        case .cancelled:
            return "Cancelled"
        case .transport(let networkError):
            return "Transport: \(String(describing: networkError))"
        case .authentication(let authError):
            return "Authentication: \(String(describing: authError))"
        case .unknown(let message):
            return message
        }
    }
}
