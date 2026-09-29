import Foundation

/// Runtime monetization switches. Values come from the server config endpoint.
///
/// Both flags fail closed. A missing cache and a failed fetch stay false, so a
/// Release binary cannot turn StoreKit on by itself.
///
/// `iosPaywallEnabled` shows the plan screen and allows purchase, restore, and
/// manage. `entitlementEnforcementEnabled` applies Free-plan usage caps in the
/// client. Server limits use the same enforcement flag.
nonisolated enum IosSubscriptionReleaseConfiguration {
    #if DEBUG
    private static var paywallOverride: Bool?
    private static var enforcementOverride: Bool?
    /// Override in unit tests when exercising the referral Settings surface.
    static var iosReferralProgramEnabled = false
    #else
    static let iosReferralProgramEnabled = false
    #endif

    static var iosPaywallEnabled: Bool {
        #if DEBUG
        if let paywallOverride { return paywallOverride }
        #endif
        return MonetizationRuntimeConfiguration.shared.iosPaywallEnabled
    }

    static var entitlementEnforcementEnabled: Bool {
        #if DEBUG
        if let enforcementOverride { return enforcementOverride }
        #endif
        return MonetizationRuntimeConfiguration.shared.entitlementEnforcementEnabled
    }

    /// Paywall / StoreKit commerce. Tracks ``iosPaywallEnabled``.
    static var iosPaidSubscriptionsEnabled: Bool {
        get { iosPaywallEnabled }
        set {
            #if DEBUG
            paywallOverride = newValue
            #endif
        }
    }

    /// Free-tier caps apply only when entitlement enforcement is on.
    static var appliesFreeTierUsageCaps: Bool {
        entitlementEnforcementEnabled
    }

    #if DEBUG
    static func setTestOverrides(paywall: Bool?, enforcement: Bool?) {
        paywallOverride = paywall
        enforcementOverride = enforcement
    }

    static func resetTestOverrides() {
        paywallOverride = nil
        enforcementOverride = nil
    }
    #endif
}
