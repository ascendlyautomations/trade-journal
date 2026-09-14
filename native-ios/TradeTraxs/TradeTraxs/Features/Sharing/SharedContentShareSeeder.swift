import Foundation

/// Seeds canonical shared entities at send time so outbound message cards render immediately.
@MainActor
enum SharedContentShareSeeder {
    static func seed(
        target: SharedContentShareTarget,
        detailCache: DetailPresentationCache,
        feedSessionStore: FeedSessionStore,
        viewerID: ProfileID
    ) {
        seed(reference: target.reference, detailCache: detailCache, feedSessionStore: feedSessionStore, viewerID: viewerID)
        if let tradeID = target.roomTradeID {
            seedTradeID(tradeID, detailCache: detailCache, feedSessionStore: feedSessionStore, viewerID: viewerID)
        }
    }

    static func seed(
        reference: SharedContentReference,
        detailCache: DetailPresentationCache,
        feedSessionStore: FeedSessionStore,
        viewerID: ProfileID
    ) {
        if let seed = feedSessionStore.lookup(reference: reference, viewerID: viewerID) {
            applyFeedSeed(seed, reference: reference, detailCache: detailCache)
            return
        }

        switch reference {
        case .feedPost(let id), .profilePost(let id):
            if detailCache.post(id: id) != nil { return }
            if let post = SocialEntityDiskCache.loadPost(id: id, viewerID: viewerID) {
                detailCache.seed(post)
                if let tradeID = post.linkedTradeID,
                   detailCache.trade(id: tradeID) == nil,
                   let trade = SocialEntityDiskCache.loadTrade(id: tradeID, viewerID: viewerID)
                {
                    detailCache.seed(trade)
                }
            }
        case .reel(let id):
            if detailCache.reel(id: id) != nil { return }
            if let reel = SocialEntityDiskCache.loadReel(id: id, viewerID: viewerID) {
                detailCache.seed(reel)
                if let tradeID = reel.linkedTradeID,
                   detailCache.trade(id: tradeID) == nil,
                   let trade = SocialEntityDiskCache.loadTrade(id: tradeID, viewerID: viewerID)
                {
                    detailCache.seed(trade)
                }
            }
        case .achievementPost(let id):
            let achievementID = AchievementID(id.rawValue)
            if detailCache.achievement(id: achievementID) != nil { return }
            if let achievement = SocialEntityDiskCache.loadAchievement(id: achievementID, viewerID: viewerID) {
                detailCache.seed(achievement)
            }
        case .trade(let id):
            seedTradeID(id, detailCache: detailCache, feedSessionStore: feedSessionStore, viewerID: viewerID)
        }
    }

    private static func seedTradeID(
        _ tradeID: TradeID,
        detailCache: DetailPresentationCache,
        feedSessionStore: FeedSessionStore,
        viewerID: ProfileID
    ) {
        if detailCache.trade(id: tradeID) != nil { return }
        if let trade = feedSessionStore.lookupTrade(id: tradeID, viewerID: viewerID) {
            detailCache.seed(trade)
            return
        }
        if let trade = SocialEntityDiskCache.loadTrade(id: tradeID, viewerID: viewerID) {
            detailCache.seed(trade)
        }
    }

    private static func applyFeedSeed(
        _ seed: FeedSessionStore.SharedContentSeed,
        reference: SharedContentReference,
        detailCache: DetailPresentationCache
    ) {
        FeedBootstrap.seedAuthor(from: seed.item, detailCache: detailCache)
        if let trade = seed.trade { detailCache.seed(trade) }
        if let post = seed.post { detailCache.seed(post) }
        if let reel = seed.reel { detailCache.seed(reel) }
        if let achievement = seed.achievement { detailCache.seed(achievement) }
        if case .feedPost = reference, seed.post == nil, seed.trade != nil {
            detailCache.seed(seed.syntheticFeedPost)
        }
    }
}
