import Foundation

/// Which Pro surfaces support the signed-in interactive sample-data preview.
nonisolated enum TraxsProPreviewFeature: String, Sendable {
    case reports
    case dashboard
    case expenseTracker
    case tradingRules
    case backtestLab
}

nonisolated enum TraxsProPreviewEntryPoint: String, Sendable {
    case reportsGate = "reports_gate"
    case dashboardGate = "dashboard_gate"
    case dashboardUpsell = "dashboard_upsell"
    case expenseTrackerGate = "expense_tracker_gate"
    case tradingRulesGate = "trading_rules_gate"
    case backtestLabGate = "backtest_lab_gate"
    case proUpgradeSheet = "pro_upgrade_sheet"
    case featurePreviewCard = "feature_preview_card"
    case previewBanner = "preview_banner"
}

enum TraxsProPreviewCatalog {
    static func supportsInteractivePreview(for feature: ProFeatureKind) -> Bool {
        switch feature {
        case .tradingReports, .premiumAnalytics, .propFirm, .backtestLab:
            return true
        default:
            return false
        }
    }

    static func supportsInteractivePreview(for reason: ProGateReason) -> Bool {
        guard case .feature(let feature) = reason else { return false }
        return supportsInteractivePreview(for: feature)
    }

    static func previewFeature(for feature: ProFeatureKind) -> TraxsProPreviewFeature? {
        switch feature {
        case .tradingReports:
            return .reports
        case .premiumAnalytics:
            return .dashboard
        case .propFirm:
            return .expenseTracker
        case .backtestLab:
            return .backtestLab
        default:
            return nil
        }
    }

    static func previewFeature(for reason: ProGateReason) -> TraxsProPreviewFeature? {
        guard case .feature(let feature) = reason else { return nil }
        return previewFeature(for: feature)
    }

    /// Paywall preview routing, explicit context wins; otherwise map from the gate reason.
    static func resolvedPreviewFeature(
        reason: ProGateReason,
        preferred: TraxsProPreviewFeature?,
        suppressPreview: Bool
    ) -> TraxsProPreviewFeature? {
        guard !suppressPreview else { return nil }
        if let preferred { return preferred }
        return previewFeature(for: reason)
    }
}