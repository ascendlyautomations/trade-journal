import Foundation

/// Shared user-facing copy for TraxsPro gates — no external purchase steering.
nonisolated enum TraxProFeatureMessaging {
    static let featureTitle = "\(MonetizationPlanCopy.proPlanName) feature"
    static let featureRequired = "This feature requires \(MonetizationPlanCopy.proPlanName)."
    static let tradeAIUnavailable = featureRequired
}