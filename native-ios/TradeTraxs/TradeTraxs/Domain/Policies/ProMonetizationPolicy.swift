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

    /// Premium dashboard chart blocks — hide only for a **confirmed** Free snapshot (`.deny`), not when entitlement is unknown.
    static func shouldHidePremiumDashboardCharts(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        guard canPresentProPaywall(
            demoModeActive: demoModeActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        ) else { return false }
        guard let profileID else { return false }
        let record = PersistedEntitlementSnapshotStore.load(userID: profileID.rawValue)
        return EntitlementSnapshotPolicy.decision(record) == .deny
    }

    /// Trading Reports catalog — same confirmed-Free semantics as premium dashboard charts (Phase 1).
    static func shouldRestrictTradingReportsCatalog(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        shouldHidePremiumDashboardCharts(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Advanced Psychology Analytics, Coach, and Trade AI — same confirmed-Free semantics as Phase 1–2.
    static func shouldRestrictPremiumPsychologyAndAI(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        shouldHidePremiumDashboardCharts(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Advanced Prop Firm Mode (detail, rules engine, payout cycles UI) — confirmed-Free semantics match Phase 1–3.
    static func shouldRestrictPropFirmMode(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        shouldHidePremiumDashboardCharts(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Backtest Lab — confirmed-Free semantics match premium dashboard / reports gating.
    static func shouldRestrictBacktestLab(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        shouldHidePremiumDashboardCharts(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }
}
