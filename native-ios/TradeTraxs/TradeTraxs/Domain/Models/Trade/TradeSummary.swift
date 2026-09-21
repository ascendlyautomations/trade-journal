import Foundation

/// Canonical list/card trade transport (Phase 8B server `trade_summary_v1`).
nonisolated struct TradeSummary: Sendable, Equatable, Hashable, Identifiable, Codable {
    var id: TradeID
    var ownerProfileID: ProfileID
    var symbol: Symbol
    var side: TradeSide
    var realizedPnL: Money?
    var riskReward: Decimal?
    var points: Decimal?
    var quantity: Decimal
    var entryAt: Date
    var exitAt: Date?
    var createdAt: Date
    var visibility: ContentVisibility
    var publicCaption: String?
    /// Viewer-aware card note line — not full journal notes.
    var notePreview: String?
    var thumbnail: MediaReference?
    var imageDisplayMode: TradeScreenshotDisplayMode
    var mode: TradeMode
    var publicAccountBadge: String?
    var durationSeconds: Int?
    var durationText: String?
}

/// Owner journal list extension — not used on public profile tab summary.
nonisolated struct TradeSummaryOwnerListMetadata: Sendable, Equatable {
    var accountID: TradingAccountID?
}

/// Owner Trades / Journal list row — canonical ``TradeSummary`` plus owner-only list fields.
nonisolated struct TradeOwnerJournalSummary: Sendable, Equatable, Identifiable {
    var summary: TradeSummary
    var accountID: TradingAccountID?
    var accountName: String?
    var strategy: String?
    var entryPrice: Decimal?
    var exitPrice: Decimal?
    var sessionLabel: String?

    var id: TradeID { summary.id }
}

/// Reserved for Feed timeline extensions (Phase 8F).
nonisolated struct TradeSummaryFeedMetadata: Sendable, Equatable {
    var feedPostID: String?
}
