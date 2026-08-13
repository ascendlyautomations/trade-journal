import Foundation

/// Coordinated first-paint (or force-refresh) load owned by a screen / domain.
///
/// Implementations are typically `enum` namespaces with a static `load` (see
/// ``ProfileBootstrap``, ``FeedBootstrap``, ``MessagingBootstrap``). Prefer
/// concurrent `async let` for independent repository calls.
///
/// Do not put UI or navigation here — only data assembly into a state snapshot / result.
protocol ScreenBootstrap {
    associatedtype Context
    associatedtype Output

    /// Executes the coordinated fan-out. Throws only for hard failures of the primary load.
    static func load(_ context: Context) async throws -> Output
}
