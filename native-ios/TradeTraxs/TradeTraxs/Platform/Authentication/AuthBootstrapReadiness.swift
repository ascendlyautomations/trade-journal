import Foundation

/// MainActor gate for session-scoped background hydration (badge, broker eligibility, etc.).
@MainActor
enum AuthBootstrapReadiness {
    /// Bound by ``CompositionRoot`` after auth + navigation exist.
    static var allowsAuthenticatedBackgroundWork: () -> Bool = { false }
}
