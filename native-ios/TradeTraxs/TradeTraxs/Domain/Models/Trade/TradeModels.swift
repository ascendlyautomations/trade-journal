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
    /// Note preview from the trade row (`notes`) when present.
    var notePreview: String?
    /// Optional setup/strategy label from `trades.strategy` when present.
    var strategy: String? = nil
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
    /// Public screenshot URL after upload (storage path or absolute URL).
    var imageURL: String? = nil
}
