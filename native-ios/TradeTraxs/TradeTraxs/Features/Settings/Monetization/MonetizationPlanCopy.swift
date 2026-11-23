import Foundation

/// Canonical Free / TraxsPro marketing copy for native monetization surfaces.
/// Align with ``lib/tradeTraxsPlans.ts`` — presentation only (not billing enforcement).
nonisolated enum MonetizationPlanCopy {
    static let freePlanName = "TradeTraxs Free"
    static let proPlanName = "TraxsPro"

    static let dashboardHeadline = "Unlock TraxsPro"
    static let dashboardSubtitle = "Take your trading to the next level."
    static let exploreTraxsProButtonTitle = "Explore TraxsPro"
    static let previewWithSampleDataButtonTitle = "Preview with Sample Data"
    static let previewProButtonTitle = "Preview Pro"
    static let previewTraxsProRulesButtonTitle = "Preview TraxsPro Rules"
    static let exitPreviewButtonTitle = "Exit Preview"
    static let traxsProPreviewGenericSubtitle = "You're exploring TraxsPro with read-only sample data."
    static let dashboardPreviewSampleDataSubtitle = "Explore TraxsPro analytics with sample trades."

    static let tradingRulesFreeTierSummary =
        "Free includes five rule families. Saved TraxsPro values stay on your account."
    static let tradingRulesPremiumSectionSubtitle =
        "Advanced risk, discipline, and performance guardrails. Your saved values stay on your account if you upgrade."

    static let dashboardPremiumPreviewTitle = "Premium Dashboard Analytics"
    static let dashboardPremiumPreviewMessage =
        "Explore hold time, trading hours, R:R targeting, setup performance, drawdown, psychology insights, and more using realistic sample trades."

    static let dashboardGateHoldTimeMessage =
        "See how hold duration lines up with outcomes across your journal."
    static let dashboardGateTradingHoursMessage =
        "Find your strongest and weakest hours with hourly performance analytics."
    static let dashboardGateRrTargetingMessage =
        "Compare planned target R:R to max R:R reached on the same trades."
    static let dashboardGateSetupPerformanceMessage =
        "See your strongest and weakest setups ranked by net realized P&L."
    static let dashboardGateDrawdownMessage =
        "Track how far equity falls from its peak trade by trade."
    static let dashboardGatePsychologyInsightsMessage =
        "Connect check-ins and discipline patterns to performance on your trading days."

    /// Per-chart unlock rows for the consolidated dashboard TraxsPro section (Free tier).
    static let dashboardPremiumAnalyticsHighlights: [PaywallHighlight] = [
        PaywallHighlight(
            id: "holdTime",
            title: "Hold Time",
            detail: dashboardGateHoldTimeMessage,
            systemImage: "hourglass"
        ),
        PaywallHighlight(
            id: "tradingHours",
            title: "Trading Hours",
            detail: dashboardGateTradingHoursMessage,
            systemImage: "clock"
        ),
        PaywallHighlight(
            id: "rrTargeting",
            title: "R:R Targeting",
            detail: dashboardGateRrTargetingMessage,
            systemImage: "scope"
        ),
        PaywallHighlight(
            id: "setupPerformance",
            title: "Setup Performance",
            detail: dashboardGateSetupPerformanceMessage,
            systemImage: "square.grid.2x2"
        ),
        PaywallHighlight(
            id: "drawdown",
            title: "Drawdown",
            detail: dashboardGateDrawdownMessage,
            systemImage: "chart.line.downtrend.xyaxis"
        ),
        PaywallHighlight(
            id: "psychologyInsights",
            title: "Psychology Insights",
            detail: dashboardGatePsychologyInsightsMessage,
            systemImage: "brain.head.profile"
        ),
    ]

    static let paywallUnlockTitle = "Unlock TraxsPro"
    static let paywallUnlockSubtitle = "Professional tools built on the journal you already trust."

    static let redeemAppleOfferCodeButtonTitle = "Redeem Apple Offer Code"
    static let offerCodeRedemptionPausedFootnote =
        "Offer code redemption opens when App Store subscriptions are enabled."

    static let proEverythingInFreeHeading = "Everything in Free, plus:"

    struct PaywallHighlight: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
    }

    /// Hero benefits on the upgrade sheet and dashboard upsell (single source).
    static let paywallHighlights: [PaywallHighlight] = [
        PaywallHighlight(
            id: "analytics",
            title: "Advanced Analytics",
            detail: "Discover deeper patterns in your performance.",
            systemImage: "chart.bar.xaxis"
        ),
        PaywallHighlight(
            id: "accountability",
            title: "Trading Accountability",
            detail: "Track your rules and trading discipline.",
            systemImage: "checkmark.shield"
        ),
        PaywallHighlight(
            id: "reports",
            title: "Reports & Backtesting",
            detail: "Review results and refine strategies.",
            systemImage: "doc.text.magnifyingglass"
        ),
        PaywallHighlight(
            id: "ai",
            title: "AI-Powered Analytics",
            detail: "Get personalized trading insights.",
            systemImage: "sparkles"
        ),
        PaywallHighlight(
            id: "accounts",
            title: "Unlimited Accounts & Copy Trading",
            detail: "Scale and manage your trading.",
            systemImage: "arrow.triangle.branch"
        ),
        PaywallHighlight(
            id: "psychology",
            title: "Psychology Insights & Coaching",
            detail: "Understand your trading behavior.",
            systemImage: "brain.head.profile"
        ),
        PaywallHighlight(
            id: "prop",
            title: "Advanced Prop Firm Tools",
            detail: "Track expenses and performance.",
            systemImage: "building.columns"
        ),
    ]

    /// Full TradeTraxs Free plan (Settings → Plan disclosure).
    static let freePlanFeatures: [String] = [
        "Up to 3 active trading accounts",
        "Unlimited manual trades and CSV imports",
        "Supported broker integrations (including Tradovate and Rithmic where available)",
        "Automatic trade syncing when connected",
        "Basic performance analytics and Trading Scorecard",
        "Trading Rules configuration",
        "Psychology check-ins and payout recording",
        "Trade Rooms and livestreams — join and host",
        "Social feed, messaging, profiles, and leaderboards",
        "\(FreeTierPolicy.dailyClipLimit) clips per UTC calendar day",
    ]

    /// Full TraxsPro add-ons (Settings → Plan and expandable paywall list).
    static let proPlanFeatures: [String] = [
        "Unlimited trading accounts and clips",
        "Advanced dashboard charts and analytics",
        "Trading Rules compliance and accountability",
        "Advanced trading insights",
        "AI Trade Analyst and Psychology Coach",
        "Psychology Insights and Trading Reports",
        "Backtest Lab",
        "Advanced Prop Firm Analytics",
        "Prop Firm Expense Tracker",
        "Copy Trading",
    ]

    /// Legacy single-line list — use ``proPlanFeatures`` in new UI.
    static var proBenefitLines: [String] { proPlanFeatures }
}