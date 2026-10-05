import Foundation

enum ProMonetizationPolicy {
    static func entitlementGatingActive(enforcement: Bool) -> Bool {
        enforcement
    }

    static func canPresentProPaywall(
        enforcement: Bool,
        paywallEnabled: Bool
    ) -> Bool {
        canPresentProPaywall(
            demoModeActive: false,
            enforcement: enforcement,
            paywallEnabled: paywallEnabled
        )
    }

    /// Demo Mode may explore Pro surfaces. Real accounts still use `isPro` plus enforcement.
    static func canPresentProPaywall(
        demoModeActive: Bool,
        enforcement: Bool,
        paywallEnabled: Bool
    ) -> Bool {
        if demoModeActive { return false }
        return enforcement && paywallEnabled
    }

    static func shouldGateProFeature(isPro: Bool, enforcement: Bool) -> Bool {
        !isPro && enforcement
    }
}
