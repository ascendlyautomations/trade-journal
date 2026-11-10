import Foundation

/// Pre–`20260914210000_drop_reels_trade_caption_check`, trade-linked reels could not persist `reels.caption`
/// (caption had to be null when `trade_id` was set). UI previously surfaced `trades.public_description`.
enum ReelCaptionLegacySupport {
    /// First moment trade-linked reels could store an independent caption (constraint dropped).
    nonisolated private static let independentCaptionCutoff: Date = {
        ISO8601.date(from: "2026-09-14T21:00:00.000Z")
            ?? Date(timeIntervalSince1970: 1_727_395_200)
    }()

    nonisolated static func shouldFillCaptionFromLinkedTrade(reel: Reel) -> Bool {
        guard reel.linkedTradeID != nil else { return false }
        guard normalized(reel.caption) == nil else { return false }
        return reel.createdAt < independentCaptionCutoff
    }

    nonisolated static func shouldFillCaptionFromLinkedTrade(
        tradeID: String?,
        createdAt: String?,
        dbCaption: String?
    ) -> Bool {
        let linked = tradeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !linked.isEmpty else { return false }
        guard normalized(dbCaption) == nil else { return false }
        guard let created = ISO8601.date(from: createdAt ?? "") else { return false }
        return created < independentCaptionCutoff
    }

    nonisolated static func tradePublicCaption(from publicDescription: String?) -> String? {
        normalized(publicDescription)
    }

    /// Profile / feed display when mapped reel still has nil caption (cache, RPC, disk).
    @MainActor
    static func displayFallbackCaption(for reel: Reel, cache: DetailPresentationCache) -> String? {
        guard shouldFillCaptionFromLinkedTrade(reel: reel),
              let tradeID = reel.linkedTradeID
        else { return nil }

        if let trade = cache.trade(id: tradeID) {
            if let caption = normalized(trade.publicCaption) { return caption }
            if let notes = normalized(trade.notes) { return notes }
            if let preview = normalized(trade.notePreview) { return preview }
        }
        if let summary = cache.tradeSummary(id: tradeID) {
            if let caption = normalized(summary.publicCaption) { return caption }
            if let preview = normalized(summary.notePreview) { return preview }
        }
        return nil
    }

    nonisolated private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
