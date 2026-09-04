import Foundation

nonisolated enum TradeSide: String, Hashable, Codable, Sendable {
    case long
    case short
}

nonisolated enum TradeMode: String, Hashable, Codable, Sendable {
    case live
    case sim
    case replay
    case backtest
    case copyTraded
}

/// Screenshot rendering — `trades.image_display_mode` (`fit` | `fill`).
nonisolated enum TradeScreenshotDisplayMode: String, Hashable, Codable, Sendable {
    case fit
    case fill

    static func resolve(_ raw: String?) -> TradeScreenshotDisplayMode {
        String(raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "fill" ? .fill : .fit
    }
}

nonisolated enum TradingAccountCategory: String, Hashable, Codable, Sendable {
    case personal
    case broker
    case propFirm
    case backtest
}

nonisolated enum TradingAccountMode: String, Hashable, Codable, Sendable {
    case live
    case sim
    case evaluation
    case funded
    case backtest

    /// Parses authoritative `accounts.mode` / denormalized trade `account_type` wire values.
    static func parseWireValue(_ raw: String?) -> TradingAccountMode? {
        let normalized = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "eval", "evaluation":
            return .evaluation
        case "funded":
            return .funded
        case "sim", "replay":
            return .sim
        case "backtest":
            return .backtest
        case "live":
            return .live
        default:
            return nil
        }
    }
}

/// Prop-firm rule columns on `accounts` — source of truth mirrors web `PropfirmAccountRules`.
nonisolated struct PropFirmAccountRules: Hashable, Codable, Sendable {
    /// DB `consistency` — max single winning trade as % of total winning-trade profit.
    var consistencyPercent: Decimal?
    /// DB `max_drawdown` — trailing max loss limit ($).
    var maxDrawdown: Decimal?
    /// DB `daily_drawdown` — worst single futures-day loss cap ($).
    var dailyDrawdown: Decimal?
    /// DB `profit_target`.
    var profitTarget: Decimal?
    /// DB `winning_days` — minimum **winning** days (not all trading days).
    var winningDaysRequired: Int?
    /// DB `winning_day_threshold` — min daily net to count as a winning day.
    var winningDayThreshold: Decimal?
    /// DB `payout_drawdown_behavior`: `reset_to_account` | `keep_trailing`.
    var payoutDrawdownBehavior: String?

    init(
        consistencyPercent: Decimal? = nil,
        maxDrawdown: Decimal? = nil,
        dailyDrawdown: Decimal? = nil,
        profitTarget: Decimal? = nil,
        winningDaysRequired: Int? = nil,
        winningDayThreshold: Decimal? = nil,
        payoutDrawdownBehavior: String? = nil
    ) {
        self.consistencyPercent = consistencyPercent
        self.maxDrawdown = maxDrawdown
        self.dailyDrawdown = dailyDrawdown
        self.profitTarget = profitTarget
        self.winningDaysRequired = winningDaysRequired
        self.winningDayThreshold = winningDayThreshold
        self.payoutDrawdownBehavior = payoutDrawdownBehavior
    }
}

/// Broker / prop / personal account under a profile.
nonisolated struct TradingAccount: Hashable, Codable, Sendable, Identifiable {
    var id: TradingAccountID
    var ownerProfileID: ProfileID
    var name: String
    var category: TradingAccountCategory
    var mode: TradingAccountMode
    var size: Money?
    var isActive: Bool
    var canAddTrades: Bool
    /// When false, account stays in Manage Accounts and history but hides from pickers.
    var showInAccountDropdowns: Bool = true
    /// Optional public profile label (e.g. Blown, Passed, Funded).
    var customPublicStatus: String? = nil
    /// Web `accounts.account_number` (optional broker/firm ID).
    var accountNumber: String? = nil
    /// Web `accounts.note`.
    var note: String? = nil
    /// Present when category is prop firm and rule columns are loaded.
    var propFirmRules: PropFirmAccountRules? = nil

    var isPropFirmAccount: Bool { category == .propFirm }
}

/// Create / edit payload mirroring web `CreateTradingAccountPayload`.
nonisolated struct TradingAccountDraft: Hashable, Codable, Sendable {
    var name: String
    /// Digits-only account value string (web `account_size`). Required on create.
    var sizeDigits: String
    var accountNumber: String
    var category: TradingAccountCategory
    var mode: TradingAccountMode
    var note: String
    var propFirmRules: PropFirmAccountRules?
}

/// Core journal trade aggregate root.
nonisolated struct Trade: Hashable, Codable, Sendable, Identifiable {
    var id: TradeID
    var ownerProfileID: ProfileID
    var accountID: TradingAccountID?
    var symbol: Symbol
    var side: TradeSide
    var mode: TradeMode
    var quantity: Decimal
    var entryPrice: Decimal?
    var exitPrice: Decimal?
    var entryAt: Date
    var exitAt: Date?
    var realizedPnL: Money?
    var riskReward: Decimal?
    var points: Decimal?
    var sessionLabel: String?
    var visibility: ContentVisibility
    var publicCaption: String?
    /// Primary screenshot from the trade row (`image_url`) when present.
    var thumbnail: MediaReference?
    /// `trades.image_display_mode` — defaults to `.fit` when unset.
    var imageDisplayMode: TradeScreenshotDisplayMode = .fit
    /// Note preview from the trade row (`notes`) when present.
    var notePreview: String?
    /// Full journal notes from `trades.notes` (owner reads / edit hydration).
    var notes: String? = nil
    /// Optional setup/strategy label from `trades.strategy` when present.
    var strategy: String? = nil
    var timeframe: String? = nil
    var newsEvent: Bool? = nil
    var confidence: Int? = nil
    var emotion: String? = nil
    var followedPlan: Bool? = nil
    var marketCondition: String? = nil
    var psychologyNotes: String? = nil
    /// Owner-only emotion after exit — `trades.exit_emotion`.
    var exitEmotion: String? = nil
    /// Owner-only execution/discipline rating 1–5 — `trades.execution_rating`.
    var executionRating: Int? = nil
    /// Authoritative hold duration from `duration_text` / `duration_seconds` when present.
    var durationText: String? = nil
    var durationSeconds: Int? = nil
    /// CSV import review flag — `trades.reviewed`.
    var reviewed: Bool? = nil
    /// Bulk CSV import marker — `trades.is_initial_import`.
    var isInitialImport: Bool? = nil
    /// Import origin — `trades.import_source` (`manual` | `csv` | `screenshot`).
    var importSource: TradeImportSource? = nil
    /// Deterministic import fingerprint — `trades.import_fingerprint`.
    var importFingerprint: String? = nil
    /// Authoritative account mode from denormalized trade fields / linked account.
    var accountMode: TradingAccountMode? = nil
    /// Compact public account badge (Eval / Funded / Live / …) from denormalized trade mode fields.
    var publicAccountBadge: String? = nil
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct TradeImage: Hashable, Codable, Sendable, Identifiable {
    var id: TradeImageID
    var tradeID: TradeID
    var media: MediaReference
    var sortOrder: Int
}

nonisolated struct TradeNote: Hashable, Codable, Sendable, Identifiable {
    var id: TradeNoteID
    var tradeID: TradeID
    var body: String
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct TradeExecution: Hashable, Codable, Sendable {
    var tradeID: TradeID
    var filledQuantity: Decimal
    var averagePrice: Decimal
    var fees: Money?
    var executedAt: Date
}

nonisolated struct TradeAnalysis: Hashable, Codable, Sendable {
    var tradeID: TradeID
    var setupTags: [String]
    var mistakes: [String]
    var grade: String?
    var notes: String?
}

nonisolated struct TradeStatistics: Hashable, Codable, Sendable {
    var tradeCount: Int
    var winCount: Int
    var lossCount: Int
    var totalPnL: Money
    var averagePnL: Money
    var averageRiskReward: Decimal?
    var winRate: Decimal
}

/// Draft used by compose / import before persistence.
///
/// Mirrors web `saveManualTrade` / Quick Trade fields. Optional review fields
/// stay nil unless the user fills Trade Review.
nonisolated struct TradeDraft: Hashable, Codable, Sendable {
    var accountID: TradingAccountID?
    /// Denormalized account columns written on insert (web parity).
    var accountName: String? = nil
    var accountSizeLabel: String? = nil
    var accountModeLabel: String? = nil
    var accountCategoryLabel: String? = nil
    /// Owner-only metadata for public-trade denormalization redaction (never sent on wire).
    var ownerAccountNumber: String? = nil
    var ownerAccountCategory: TradingAccountCategory? = nil
    var ownerAccountMode: TradingAccountMode? = nil
    var symbol: Symbol
    var side: TradeSide
    var mode: TradeMode
    var quantity: Decimal
    var entryPrice: Decimal?
    var exitPrice: Decimal?
    var entryAt: Date
    var exitAt: Date?
    var realizedPnL: Money?
    var riskReward: Decimal? = nil
    var points: Decimal? = nil
    var sessionLabel: String? = nil
    var strategy: String? = nil
    var visibility: ContentVisibility
    var publicCaption: String?
    var noteBody: String?
    var timeframe: String? = nil
    var newsEvent: Bool = false
    var confidence: Int? = nil
    var emotion: String? = nil
    var followedPlan: Bool = false
    var marketCondition: String? = nil
    var psychologyNotes: String? = nil
    var exitEmotion: String? = nil
    var executionRating: Int? = nil
    var imageDisplayMode: TradeScreenshotDisplayMode = .fit
    var durationSeconds: Int? = nil
    var durationText: String? = nil
    /// Public screenshot URL after upload (storage path or absolute URL).
    var imageURL: String? = nil
    /// Import origin when created via bulk import.
    var importSource: TradeImportSource? = nil
    /// Deterministic import fingerprint for idempotent re-import.
    var importFingerprint: String? = nil
}
