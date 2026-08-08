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
nonisolated struct TradeDraft: Hashable, Codable, Sendable {
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
    var visibility: ContentVisibility
    var publicCaption: String?
    var noteBody: String?
}
