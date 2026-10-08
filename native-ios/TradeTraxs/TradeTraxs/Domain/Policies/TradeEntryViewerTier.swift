import Foundation

/// TraxPro vs free tier for trade-entry gating (nonisolated; safe from ``FreePlanTradeAccountPolicy``).
nonisolated enum TradeEntryViewerTier: Equatable, Sendable {
    case pro
    case free
}
