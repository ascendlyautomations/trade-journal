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

    // MARK: - Future extension points
    // case validation(ValidationError)
    // case persistence(PersistenceError)
}
