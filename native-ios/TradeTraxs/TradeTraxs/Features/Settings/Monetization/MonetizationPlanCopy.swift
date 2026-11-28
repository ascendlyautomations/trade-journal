import Foundation

/// Canonical Free / TraxsPro marketing copy for native monetization surfaces.
/// Align with ``lib/tradeTraxsPlans.ts``, presentation only (not billing enforcement).
nonisolated enum MonetizationPlanCopy {
    static let freePlanName = "TradeTraxs Free"
    static let proPlanName = "TraxsPro"

    static let dashboardHeadline = "Unlock TraxsPro"
    static let dashboardSubtitle = "Take your trading to the next level."
    static let exploreTraxsProButtonTitle = "Explore TraxsPro"
    static let previewWithSampleDataButtonTitle = "Preview with Sample Data"
    static let previewProButtonTitle = "Preview Pro"
    static let paywallPreviewProBadge = "(Pro)"
    static let paywallImprovementSectionTitle = "How TraxsPro Helps You Improve"

    static func paywallPreviewFeatureTitle(for feature: TraxsProPreviewFeature) -> String {
        switch feature {
        case .reports:
            return "Preview Reports"
        case .expenseTracker:
            return "Preview Expense Tracker"
        case .dashboard:
            return "Preview Dashboard"
        case .tradingRules:
            return "Preview Trading Rules"
        case .backtestLab:
            return "Preview Backtest"
        }
    }
    static let previewTraxsProRulesButtonTitle = "Preview TraxsPro Rules"
    static let exitPreviewButtonTitle = "Exit Preview"
    static let traxsProPreviewGenericSubtitle = "You're exploring TraxsPro with read-only sample data."
    static let dashboardPreviewSampleDataSubtitle = "Explore TraxsPro analytics with sample trades."
    static let reportsPreviewSampleDataSubtitle = "Review trading and psychology reports with sample trades."
    static let expenseTrackerPreviewSampleDataSubtitle = "Track prop firm costs and payouts with sample data."
    static let tradingRulesPreviewSampleDataSubtitle = "Explore TraxsPro rule compliance with sample trades."
    static let backtestLabPreviewSampleDataSubtitle =
        "Explore backtest calendars, strategy breakdowns, and trade history with sample data."
    static let backtestLabFeatureGateTitle = "TraxsPro Backtest Lab"
    static let backtestLabFeatureGateMessage =
        "Review backtest performance, calendars, and strategy breakdowns with TraxsPro."
    static let tradingRulesAnalyticsPreviewSampleDataNote =
        "Example rule checks and trades only — not your actual trading data."
    static let tradingRulesAnalyticsPreviewListSubtitle =
        "Sample compliance analytics from the demo journal."

    static let reportsFeatureGateTitle = "TraxsPro Reports"
    static let reportsFeatureGateMessage =
        "Performance and psychology report reviews are included with TraxsPro."

    static let tradingRulesFreeTierSummary =
        "Free includes five rule families. Saved TraxsPro values stay on your account."
    static let tradingRulesPremiumSectionSubtitle =
        "Advanced risk, discipline, and performance guardrails. Your saved values stay on your account if you upgrade."

    static let dashboardPremiumPreviewTitle = "Premium Dashboard Analytics"
    static let dashboardPremiumPreviewMessage =
        "Explore hold time, trading hours, R:R targeting, setup performance, drawdown, psychology insights, and more using realistic sample trades."

    static let tradeDetailPremiumHeadline = "Unlock deeper trade insights"
    static let tradeDetailPremiumSubtitle =
        "See how each trade fits your journal with TraxsPro."
    static let tradeDetailSampleDataBadge = "Sample data"
    static let tradeDetailPremiumPreviewTitle = "Preview on this trade"
    static let tradeDetailPremiumPreviewMessage =
        "Sample analytics below show what TraxsPro unlocks on your trade detail page."

    static let tradeDetailPremiumHighlights: [PaywallHighlight] = [
        PaywallHighlight(
            id: "trade_ai",
            title: "Trade AI",
            detail: "Coach prompts and custom questions on every trade.",
            systemImage: "brain.head.profile"
        ),
        PaywallHighlight(
            id: "trade_comparison",
            title: "Compared to Your Trades",
            detail: "P&L, R:R, and hold time vs your recent average.",
            systemImage: "arrow.left.arrow.right"
        ),
        PaywallHighlight(
            id: "ticker_history",
            title: "Your Ticker History",
            detail: "Win rate, profit factor, and ticker-specific context.",
            systemImage: "clock.arrow.circlepath"
        ),
    ]

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

    static let psychologyAnalyticsPreviewSampleDataNote =
        "Example check-ins and trades only — not your actual trading history."
    static let psychologyAnalyticsFreePreviewHistorySubtitle =
        "Explore how daily check-ins line up with trades in Check-In History."
    static let psychologyAnalyticsPreviewHistoryListSubtitle =
        "Sample check-in days from the demo journal."

    static let scorecardPsychologyGateTitle = "Unlock Your Trading Psychology"
    static let scorecardPsychologyGateMessage =
        "Understand how your emotions, mindset, and trading habits impact your performance. Identify behavioral patterns and build better trading discipline."
    static let previewPsychologyAnalyticsButtonTitle = "Preview Psychology Analytics"
    static let upgradeToTraxsProButtonTitle = "Upgrade to TraxsPro"

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

    static let redeemAppleOfferCodeButtonTitle = "Redeem Offer Code"
    static let offerCodeRedemptionPausedFootnote =
        "Offer code redemption opens when App Store subscriptions are enabled."

    static let proEverythingInFreeHeading = "Everything in Free, plus:"

    static let settingsFreePlanIncludedTitle = "What's Included in TradeTraxs Free"
    static let settingsTraxProUnlockTitle = "What You Unlock with TraxsPro"
    static let settingsTraxProIncludedTitle = "What's Included in TraxsPro"
    static let settingsChoosePlanTitle = "Choose Your Plan"
    static let settingsCurrentPlanTitle = "Your Current Plan"
    static let lifetimeGrantedTraxProAppreciation =
        "Thank you for being an early TradeTraxs user! You've been granted free TraxsPro access for life! 🎉"
    static let freePlanPriceLabel = "$0"
    static let freePlanShortDescription = "Core journaling and community features at no cost."

    /// Compact Settings → Plan summary (expandable, collapsed by default).
    static let freePlanSummaryHighlights: [PaywallHighlight] = [
        PaywallHighlight(
            id: "journal",
            title: "Journal & imports",
            detail: "Unlimited manual trades, CSV imports, and broker sync where available.",
            systemImage: "book.closed"
        ),
        PaywallHighlight(
            id: "analytics",
            title: "Basic analytics",
            detail: "Trading Scorecard and essential performance views.",
            systemImage: "chart.bar"
        ),
        PaywallHighlight(
            id: "rules",
            title: "Trading rules",
            detail: "Five rule families on Free; saved values stay on your account.",
            systemImage: "checkmark.shield"
        ),
        PaywallHighlight(
            id: "social",
            title: "Community & rooms",
            detail: "Feed, messaging, Trade Rooms, profiles, and daily clips.",
            systemImage: "person.2"
        ),
        PaywallHighlight(
            id: "accounts",
            title: "Up to 3 accounts",
            detail: "Active accounts plus check-ins, payouts, and calendar.",
            systemImage: "tray.full"
        ),
    ]

    static let traxProUnlockHighlights: [PaywallHighlight] = [
        PaywallHighlight(
            id: "advancedAnalytics",
            title: "Advanced analytics",
            detail: "Premium dashboard charts, hold time, hours, R:R, setup, and drawdown.",
            systemImage: "chart.bar.xaxis"
        ),
        PaywallHighlight(
            id: "discipline",
            title: "Trading discipline",
            detail: "Rules compliance, violation trends, and accountability analytics.",
            systemImage: "checkmark.shield.fill"
        ),
        PaywallHighlight(
            id: "reports",
            title: "Reports & backtesting",
            detail: "Trading and psychology reports plus Backtest Lab.",
            systemImage: "doc.text.magnifyingglass"
        ),
        PaywallHighlight(
            id: "psychology",
            title: "Psychology & AI",
            detail: "Psychology Insights, Coach, and AI Trade Analyst.",
            systemImage: "brain.head.profile"
        ),
        PaywallHighlight(
            id: "prop",
            title: "Prop firm toolkit",
            detail: "Expense Tracker and advanced prop firm analytics.",
            systemImage: "building.columns"
        ),
        PaywallHighlight(
            id: "scale",
            title: "Unlimited scale",
            detail: "Unlimited accounts, clips, and copy trading.",
            systemImage: "infinity"
        ),
    ]

    static func settingsPlanPeriodBlurb(for product: StoreKitTraxProProduct) -> String {
        let label = product.subscriptionPeriodLabel.lowercased()
        if label.contains("year") {
            return "One payment per year, best long-term value."
        }
        if label.contains("6") && label.contains("month") {
            return "Six months of TraxsPro, billed once."
        }
        if label == "monthly" || (label.contains("month") && !label.contains("6")) {
            return "Flexible monthly billing, cancel anytime."
        }
        return "Auto-renews until cancelled in Apple ID Subscriptions."
    }

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

    /// Outcome-focused copy in the paywall improvement disclosure (not a feature checklist).
    static let paywallOutcomeHighlights: [PaywallHighlight] = [
        PaywallHighlight(
            id: "edge",
            title: "Find your trading edge",
            detail: "Discover which setups, sessions, and habits produce your best results.",
            systemImage: "lightbulb.max"
        ),
        PaywallHighlight(
            id: "discipline",
            title: "Improve discipline",
            detail: "Identify rule violations and patterns behind avoidable losses.",
            systemImage: "checkmark.shield"
        ),
        PaywallHighlight(
            id: "psychology",
            title: "Understand your psychology",
            detail: "Recognize emotional triggers and behavioral trends.",
            systemImage: "brain.head.profile"
        ),
        PaywallHighlight(
            id: "expenses",
            title: "Manage trading expenses",
            detail: "Track prop firm costs, payouts, and profitability.",
            systemImage: "dollarsign.circle"
        ),
        PaywallHighlight(
            id: "strategy",
            title: "Refine your strategy",
            detail: "Use deeper reports and backtesting to evaluate performance.",
            systemImage: "chart.xyaxis.line"
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
        "Trade Rooms and livestreams, join and host",
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

    /// Legacy single-line list, use ``proPlanFeatures`` in new UI.
    static var proBenefitLines: [String] { proPlanFeatures }
}