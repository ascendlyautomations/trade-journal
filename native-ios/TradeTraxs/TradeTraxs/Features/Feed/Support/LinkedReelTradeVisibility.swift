import Foundation

/// Resolve whether a clip may show its Linked Trade block (display-only; does not mutate Supabase).
enum LinkedReelTradeVisibility {
    /// Trade returned from reel detail fetch / authoritative owner cache — never stale list seeds alone.
    static func resolvedTrade(
        reel: Reel,
        embeddedTrade: Trade?,
        cache: DetailPresentationCache,
        viewerID: ProfileID?
    ) -> Trade? {
        guard let tradeID = reel.linkedTradeID else { return nil }

        let resolved: Trade?
        if let embedded = embeddedTrade, embedded.id == tradeID {
            resolved = embedded
        } else {
            let isReelOwner = viewerID == reel.authorProfileID
            if isReelOwner,
               let cached = cache.trade(id: tradeID),
               TradeDetailCompleteness.isAuthoritative(
                   cache.tradeAuthority(for: tradeID) ?? .listSeed
               )
            {
                resolved = cached
            } else {
                resolved = nil
            }
        }

        guard let resolved, canViewerSeeLinkedTrade(trade: resolved, reel: reel, viewerID: viewerID) else {
            return nil
        }
        return resolved
    }

    /// Clip author always sees the linked journal row; everyone else requires a public trade.
    static func canViewerSeeLinkedTrade(
        trade: Trade,
        reel: Reel,
        viewerID: ProfileID?
    ) -> Bool {
        if viewerID == reel.authorProfileID { return true }
        return trade.visibility == .public
    }

    /// Drop local clip→trade index only when Supabase cleared `trade_id` (deleted), not when hidden by visibility.
    @discardableResult
    static func reconcileOrphanedReelLink(
        reel: Reel,
        cache: DetailPresentationCache,
        serverTradeLinkRemoved: Bool
    ) -> Reel {
        guard serverTradeLinkRemoved, reel.linkedTradeID != nil else { return reel }
        cache.clearReelTradeLink(reel: reel)
        var unlinked = reel
        unlinked.linkedTradeID = nil
        return unlinked
    }
}
