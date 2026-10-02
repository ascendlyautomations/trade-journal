import Foundation

enum ProMonetizationPolicy {
    static func entitlementGatingActive(enforcement: Bool) -> Bool {
        enforcement
    }

    static func canPresentProPaywall(
        enforcement: Bool,
        paywallEnabled: Bool
    ) -> Bool {
        enforcement && paywallEnabled
    }

    static func shouldGateProFeature(isPro: Bool, enforcement: Bool) -> Bool {
        !isPro && enforcement
    }
}
