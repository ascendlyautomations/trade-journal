import Foundation

/// Profile → Trades tab: minimal linked-clip metadata for trade cards (web `fetchReelsByTradeIds`).
enum ProfileTradeLinkedReelsHydrator {
    static func hydrateMissing(
        tradeIDs: [TradeID],
        profileID: ProfileID,
        feed: any FeedRepository,
        detailCache: DetailPresentationCache,
        isHydrationCurrent: @escaping @MainActor () -> Bool = { true }
    ) async {
        let missing = tradeIDs.filter { detailCache.reel(linkedTo: $0) == nil }
        guard !missing.isEmpty else { return }
        guard isHydrationCurrent() else { return }
        guard let reels = try? await feed.reels(
            linkedToTradeIDs: missing,
            ownerID: profileID
        ) else {
            return
        }
        guard isHydrationCurrent() else { return }
        let toSeed = reels.filter { reel in
            guard let tradeID = reel.linkedTradeID else { return false }
            return detailCache.reel(linkedTo: tradeID) == nil
        }
        guard !toSeed.isEmpty else { return }
        guard isHydrationCurrent() else { return }
        detailCache.seed(reels: toSeed)
    }
}