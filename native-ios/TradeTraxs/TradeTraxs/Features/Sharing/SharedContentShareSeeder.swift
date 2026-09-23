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
            if let post = SocialEntityPersistedCacheCoordinator.loadPost(
                id: id,
                viewerID: viewerID,
                purpose: "sharedContentShareSeeder"
            ) {
                detailCache.seed(post)
                if let tradeID = post.linkedTradeID,
                   detailCache.tradeSummary(id: tradeID) == nil,
                   let summary = SocialEntityPersistedCacheCoordinator.loadTradeSummary(
                       id: tradeID,
                       viewerID: viewerID,
                       purpose: "sharedContentShareSeeder.linkedTrade"
                   )
                {
                    detailCache.seedPresentationSeed(summary)
                }
            }
        case .reel(let id):
            if detailCache.reel(id: id) != nil { return }
            if let reel = SocialEntityPersistedCacheCoordinator.loadReel(
                id: id,
                viewerID: viewerID,
                purpose: "sharedContentShareSeeder"
            ) {
                detailCache.seed(reel)
                if let tradeID = reel.linkedTradeID,
                   detailCache.tradeSummary(id: tradeID) == nil,
                   let summary = SocialEntityPersistedCacheCoordinator.loadTradeSummary(
                       id: tradeID,
                       viewerID: viewerID,
                       purpose: "sharedContentShareSeeder.linkedTrade"
                   )
                {
                    detailCache.seedPresentationSeed(summary)
                }
            }
        case .achievementPost(let id):
            let achievementID = AchievementID(id.rawValue)
            if detailCache.achievement(id: achievementID) != nil { return }
            if let achievement = SocialEntityPersistedCacheCoordinator.loadAchievement(
                id: achievementID,
                viewerID: viewerID,
                purpose: "sharedContentShareSeeder"
            ) {
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
        if detailCache.tradeSummary(id: tradeID) != nil { return }
        if let summary = feedSessionStore.lookupTradeSummary(id: tradeID, viewerID: viewerID) {
            detailCache.seedPresentationSeed(summary)
            return
        }
        if let summary = SocialEntityPersistedCacheCoordinator.loadTradeSummary(
            id: tradeID,
            viewerID: viewerID,
            purpose: "sharedContentShareSeeder.trade"
        ) {
            detailCache.seedPresentationSeed(summary)
        }
    }

    private static func applyFeedSeed(
        _ seed: FeedSessionStore.SharedContentSeed,
        reference: SharedContentReference,
        detailCache: DetailPresentationCache
    ) {
        FeedBootstrap.seedAuthor(from: seed.item, detailCache: detailCache)
        if let summary = seed.tradeSummary {
            detailCache.seedPresentationSeed(DetailPresentationSeed(summary: summary))
        }
        if let post = seed.post { detailCache.seed(post) }
        if let reel = seed.reel { detailCache.seed(reel) }
        if let achievement = seed.achievement { detailCache.seed(achievement) }
        if case .feedPost = reference, seed.post == nil, seed.tradeSummary != nil {
            detailCache.seed(seed.syntheticFeedPost)
        }
    }
}
