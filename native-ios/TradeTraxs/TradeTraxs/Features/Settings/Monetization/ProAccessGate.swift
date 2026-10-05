import Foundation

/// Client-side pre-action Pro gates — backend remains authoritative.
@MainActor
enum ProAccessGate {
    static func shouldPresentPaywall(profileID: ProfileID?) -> Bool {
        guard ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        ) else { return false }
        guard let profileID else { return false }
        return !TradeEntryEntitlementGate.viewerHasTraxProAccess(profileID: profileID)
    }

    /// Returns `true` when the paywall was shown (caller should abort the action).
    @discardableResult
    static func presentFeatureIfNeeded(_ feature: ProFeatureKind, profileID: ProfileID?) -> Bool {
        guard shouldPresentPaywall(profileID: profileID) else { return false }
        ProUpgradeCoordinator.shared.present(reason: .feature(feature))
        return true
    }
}
