import Foundation

/// How premium surfaces render when monetization enforcement is on.
enum ProPremiumFeaturePresentation: Equatable, Sendable {
    case unrestricted
    case lockedPreview
    case verifyingEntitlement
}

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

    // MARK: - Dashboard chart entitlements
    //
    // TraxsPro-exclusive charts (``premiumFeaturePresentation`` → ``unrestricted`` or preview):
    // Hold Time, Trading Hours, R:R Targeting, Setup Performance, Drawdown.
    // Free tier keeps equity hero, win rate / P&L KPIs, Avg Targeted R:R chip, and standard
    // distribution charts (win-loss, sessions, weekdays, long/short, symbols). Trade journal
    // Target R:R fields are unchanged.

    /// Premium dashboard chart blocks, upgrade preview for verified Free; verification UI for unknown.
    @MainActor
    static func premiumFeaturePresentation(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> ProPremiumFeaturePresentation {
        if TraxsProPreviewSession.shared.isDashboardPreviewActive {
            return .unrestricted
        }
        if demoModeActive || !IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled {
            return .unrestricted
        }
        switch TraxProEffectiveEntitlement.clientAccess(
            profileID: profileID,
            demoModeActive: demoModeActive
        ) {
        case .unrestricted, .pro:
            return .unrestricted
        case .free:
            return .lockedPreview
        case .unknown:
            return .verifyingEntitlement
        }
    }

    /// Premium dashboard chart blocks, locked preview for verified Free (use ``premiumFeaturePresentation`` in UI).
    @MainActor
    static func shouldHidePremiumDashboardCharts(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        premiumFeaturePresentation(demoModeActive: demoModeActive, profileID: profileID) == .lockedPreview
    }

    /// Trading Rules compliance analytics, verified Free users when enforcement is on.
    @MainActor
    static func shouldRestrictTradingRulesComplianceAnalytics(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        if TraxsProPreviewSession.shared.isDashboardPreviewActive
            || TraxsProPreviewSession.shared.isTradingRulesPreviewActive
        {
            return false
        }
        return TraxProEffectiveEntitlement.shouldRestrictPremiumFeatures(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Whether to run trading-rules compliance math (basic Free or full TraxsPro).
    @MainActor
    static func shouldComputeTradingRulesCompliance(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        switch TraxProEffectiveEntitlement.clientAccess(
            profileID: profileID,
            demoModeActive: demoModeActive
        ) {
        case .unrestricted, .pro, .free:
            return true
        case .unknown:
            return false
        }
    }

    /// Free tier evaluates a subset of rule families; TraxsPro uses all rules (`nil` filter).
    @MainActor
    static func tradingRulesComplianceRuleFilter(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Set<TradingRulesComplianceAnalytics.RuleID>? {
        let isFree = shouldRestrictTradingRulesComplianceAnalytics(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
        return TradingRulesPlanTier.complianceRuleFilter(isFreeTier: isFree)
    }

    /// Prop Firm Expense Tracker, verified Free when enforcement is on.
    @MainActor
    static func shouldRestrictPropFirmExpenseTracker(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        TraxProEffectiveEntitlement.shouldRestrictPremiumFeatures(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    @MainActor
    static func includesPremiumDashboardAnalytics(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        if TraxsProPreviewSession.shared.isDashboardPreviewActive {
            return true
        }
        return premiumFeaturePresentation(demoModeActive: demoModeActive, profileID: profileID) == .unrestricted
    }

    @MainActor
    static func shouldShowEntitlementVerification(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        TraxProEffectiveEntitlement.shouldShowEntitlementVerification(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Trading Reports catalog, same confirmed-Free semantics as premium dashboard charts (Phase 1).
    @MainActor
    static func shouldRestrictTradingReportsCatalog(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        if TraxsProPreviewSession.shared.isReportsPreviewActive {
            return false
        }
        return TraxProEffectiveEntitlement.shouldRestrictPremiumFeatures(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Advanced Psychology Analytics, Coach, and Trade AI, verified Free users when enforcement is on.
    @MainActor
    static func shouldRestrictPremiumPsychologyAndAI(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        if TraxsProPreviewSession.shared.isDashboardPreviewActive {
            return false
        }
        return TraxProEffectiveEntitlement.shouldRestrictPremiumFeatures(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Advanced Prop Firm Mode (detail, rules engine, payout cycles UI).
    @MainActor
    static func shouldRestrictPropFirmMode(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        TraxProEffectiveEntitlement.shouldRestrictPremiumFeatures(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }

    /// Backtest Lab, verified Free users when enforcement is on.
    @MainActor
    static func shouldRestrictBacktestLab(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        TraxProEffectiveEntitlement.shouldRestrictPremiumFeatures(
            demoModeActive: demoModeActive,
            profileID: profileID
        )
    }
}
