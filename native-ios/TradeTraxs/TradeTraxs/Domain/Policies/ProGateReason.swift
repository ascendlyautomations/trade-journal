import Foundation

/// Shared Pro gate semantics — keep aligned with ``lib/proGateReason.ts``.
enum ProLimitKind: String, Sendable {
    case accountCount = "account_count"
    case dailyTrades = "daily_trades"
    case dailyPosts = "daily_posts"
    case dailyClips = "daily_clips"
    case dailyDirectMessages = "daily_direct_messages"
    case csvImportCooldown = "csv_import_cooldown"
}

enum ProFeatureKind: String, Sendable {
    case aiAnalyst = "ai_analyst"
    case backtestLab = "backtest_lab"
    case propFirm = "prop_firm"
    case copyTrading = "copy_trading"
    case premiumAnalytics = "premium_analytics"
    case tradingReports = "trading_reports"
    case performanceExports = "performance_exports"
    case generic
}

enum ProGateReason: Sendable {
    case limit(ProLimitKind)
    case feature(ProFeatureKind)

    var sheetTitle: String {
        switch self {
        case .limit:
            return "Free Plan Limit Reached"
        case .feature:
            return "TraxPro Required"
        }
    }

    var detailMessage: String {
        switch self {
        case .limit(let kind):
            switch kind {
            case .accountCount:
                return "Your Free plan includes up to \(FreeTierPolicy.maxTradeEntryAccounts) trading accounts total."
            case .dailyTrades:
                return "Manual trade entry is included on the Free plan."
            case .dailyPosts:
                return "Posts are included on the Free plan."
            case .dailyClips:
                return "Your Free plan includes \(FreeTierPolicy.dailyClipLimit) Clips per UTC calendar day."
            case .dailyDirectMessages:
                return "Direct messages are included on the Free plan."
            case .csvImportCooldown:
                return "CSV import is included on the Free plan."
            }
        case .feature(let feature):
            switch feature {
            case .copyTrading:
                return "Copy Trading lets you record one trade across multiple linked accounts."
            case .aiAnalyst:
                return "AI Trade Analyst is available with TraxPro."
            case .backtestLab:
                return "Backtest Lab is available with TraxPro."
            case .propFirm:
                return "Advanced Prop Firm Analytics are available with TraxPro."
            case .premiumAnalytics:
                return "Advanced performance analytics are available with TraxPro."
            case .tradingReports:
                return "Trading reports are available with TraxPro."
            case .performanceExports:
                return "Performance exports are available with TraxPro."
            case .generic:
                return "This feature is available with TraxPro."
            }
        }
    }

    var upsellFooter: String {
        "Upgrade to TraxPro for unlimited active accounts, unlimited Clips, and professional tools."
    }

    /// Legacy subtitle — prefer ``detailMessage`` in new UI.
    var subtitle: String { detailMessage }
}

enum ProGateReasonParser {
    static let proLimitReachedCode = "PRO_LIMIT_REACHED"

    static func limit(fromLegacyCode code: String) -> ProLimitKind? {
        let head = code.split(separator: ":").first.map(String.init) ?? code
        let upper = head.uppercased()
        switch upper {
        case "FREE_PLAN_ACCOUNT_LIMIT": return .accountCount
        case "FREE_PLAN_DAILY_TRADE_LIMIT": return .dailyTrades
        case "FREE_PLAN_DAILY_POST_LIMIT": return .dailyPosts
        case "FREE_PLAN_DAILY_CLIP_LIMIT", "FREE_PLAN_REELS_LIMIT": return .dailyClips
        case "FREE_PLAN_DAILY_DM_LIMIT": return .dailyDirectMessages
        case "TRAXPRO_COPY_TRADING_REQUIRED": return nil
        default:
            if upper.contains("CSV"), upper.contains("IMPORT") || upper.contains("COOLDOWN") {
                return .csvImportCooldown
            }
            return nil
        }
    }

    static func feature(fromToken token: String) -> ProFeatureKind? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ai_analyst": return .aiAnalyst
        case "backtest_lab": return .backtestLab
        case "prop_firm": return .propFirm
        case "copy_trading": return .copyTrading
        case "premium_analytics": return .premiumAnalytics
        case "trading_reports": return .tradingReports
        case "performance_exports": return .performanceExports
        default:
            return nil
        }
    }

    /// Legitimate Free-plan limits and Pro features only — never RLS, auth, or validation noise.
    static func reason(from error: Error) -> ProGateReason? {
        if let structured = structuredReason(from: error) {
            return structured
        }
        if let feature = feature(from: error) {
            return .feature(feature)
        }
        if let limit = limit(from: error) {
            return .limit(limit)
        }
        return nil
    }

    static func structuredReason(from error: Error) -> ProGateReason? {
        guard let object = jsonObject(from: error) else { return nil }
        let code = (object["code"] as? String ?? object["error"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard code == proLimitReachedCode else { return nil }
        let limitRaw = (object["limit"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !limitRaw.isEmpty else { return nil }
        if let feature = feature(fromToken: limitRaw) {
            return .feature(feature)
        }
        if let limit = ProLimitKind(rawValue: limitRaw) {
            return .limit(limit)
        }
        return nil
    }

    static func feature(from error: Error) -> ProFeatureKind? {
        if let domain = error as? DomainError {
            switch domain {
            case .subscription(.proRequired):
                return .generic
            case .subscription(.message(let message)):
                return feature(fromMessage: message)
            default:
                break
            }
        }
        if let app = error as? AppError, case .unknown(let message) = app {
            return feature(fromMessage: message)
        }
        return nil
    }

    static func limit(from error: Error) -> ProLimitKind? {
        if let payload = parseStructuredLimitPayload(from: error) {
            return payload
        }
        if let domain = error as? DomainError {
            switch domain {
            case .businessRule(.message(let message)):
                return limit(fromMessage: message)
            case .businessRule(.dailyLimitExceeded):
                return .dailyTrades
            default:
                break
            }
        }
        if let app = error as? AppError, case .unknown(let message) = app {
            if let parsed = limit(fromMessage: message) { return parsed }
        }
        return limit(fromMessage: String(describing: error))
    }

    private static func limit(fromMessage message: String) -> ProLimitKind? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isStaleNonLimitCopy(trimmed) { return nil }
        if let structured = structuredReason(from: AppError.unknown(message: trimmed)),
           case .limit(let kind) = structured
        {
            return kind
        }
        if let legacy = limit(fromLegacyCode: trimmed) { return legacy }
        let upper = trimmed.uppercased()
        if upper.contains("FREE_PLAN") {
            return limit(fromLegacyCode: upper)
        }
        if upper.contains("FREE PLAN"), upper.contains("ACCOUNT"), upper.contains("LIMIT") {
            return .accountCount
        }
        if upper.contains("CSV"), upper.contains("IMPORT") || upper.contains("COOLDOWN") {
            return .csvImportCooldown
        }
        return nil
    }

    private static func feature(fromMessage message: String) -> ProFeatureKind? {
        let lowered = message.lowercased()
        if lowered.contains("traxpro_copy_trading") {
            return .copyTrading
        }
        if lowered.contains("copy trading") || lowered.contains("copy_trading") {
            return .copyTrading
        }
        if lowered.contains("ai analyst") || lowered.contains("ai_analyst") || lowered.contains("trade analyst") {
            return .aiAnalyst
        }
        if lowered.contains("backtest lab") || lowered.contains("backtest_lab") { return .backtestLab }
        if lowered.contains("prop firm") || lowered.contains("prop_firm") { return .propFirm }
        if lowered.contains("premium analytics") || lowered.contains("advanced analytics") {
            return .premiumAnalytics
        }
        if lowered.contains("trading report") { return .tradingReports }
        if lowered.contains("performance export") { return .performanceExports }
        if ProEntitlementResponseSanitizer.containsPurchaseSteering(message) {
            return .generic
        }
        return nil
    }

    /// Reject obsolete copy that is not a current Free-plan cap signal.
    private static func isStaleNonLimitCopy(_ message: String) -> Bool {
        let lowered = message.lowercased()
        if lowered.contains("public trade") && lowered.contains("per day") && !lowered.contains("free_plan") {
            return true
        }
        return false
    }

    private static func parseStructuredLimitPayload(from error: Error) -> ProLimitKind? {
        if case .limit(let kind) = structuredReason(from: error) {
            return kind
        }
        return nil
    }

    private static func jsonObject(from error: Error) -> [String: Any]? {
        let candidates: [String]
        if let app = error as? AppError, case .unknown(let message) = app {
            candidates = [message]
        } else {
            candidates = [String(describing: error)]
        }
        for text in candidates {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            return object
        }
        return nil
    }
}

/// Presents upgrade sheet for Pro limits/features; returns user-facing fallback when not gated.
@MainActor
enum ProLimitPresentation {
    @discardableResult
    static func presentUpgradeIfProGate(_ error: Error) -> Bool {
        guard let reason = ProGateReasonParser.reason(from: error) else { return false }
        guard ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        ) else { return false }
        ProUpgradeCoordinator.shared.present(reason: reason)
        return true
    }

    @discardableResult
    static func presentUpgradeIfProLimit(_ error: Error) -> Bool {
        presentUpgradeIfProGate(error)
    }

    static func isProGateError(_ error: Error) -> Bool {
        ProGateReasonParser.reason(from: error) != nil
    }

    static func userMessageUnlessProLimit(_ error: Error) -> String {
        if presentUpgradeIfProGate(error) { return "" }
        return UserFacingError.message(for: error)
    }
}
