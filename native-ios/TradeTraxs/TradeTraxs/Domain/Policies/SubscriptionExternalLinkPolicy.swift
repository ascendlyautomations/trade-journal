import Foundation

/// Blocks native fall-through to external subscription checkout pages.
nonisolated enum SubscriptionExternalLinkPolicy {
    private static let blockedPathSegments: Set<String> = [
        "pricing",
        "checkout",
        "subscribe",
        "billing",
        "upgrade",
        "choose-plan",
        "finish-trial",
    ]

    /// Returns true when a TradeTraxs HTTPS URL must not open in Safari from native routing.
    static func shouldSuppressBrowserFallback(for url: URL) -> Bool {
        let parts = url.pathComponentsFiltered.map { $0.lowercased() }
        return parts.contains(where: blockedPathSegments.contains)
    }
}
