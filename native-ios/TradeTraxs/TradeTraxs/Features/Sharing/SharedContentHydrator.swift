import Foundation

/// Shared structured-content hydration for DM + Trade Room message cards.
///
/// Resolution order: in-memory detail cache → feed session cache → network (parallel per type).
@MainActor
enum SharedContentHydrator {
    private enum ParallelFetchResult: Sendable {
        case post(PostID, Post)
        case reel(ReelID, Reel, embeddedTrade: Trade?)
        case achievement(AchievementID, Achievement)
        case unavailable(String)
    }
    struct Context {
        let detailCache: DetailPresentationCache
        let feedSessionStore: FeedSessionStore
        let viewerID: ProfileID?
        let tradesRepo: (any TradeRepository)?
        let feedRepo: (any FeedRepository)?
        let achievementsRepo: (any AchievementRepository)?
        let profilesRepo: any ProfileRepository
    }

    struct Snapshot {
        var sharedTrades: [TradeID: Trade]
        var sharedPosts: [PostID: Post]
        var sharedReels: [ReelID: Reel]
        var sharedAchievements: [AchievementID: Achievement]
        var unavailableSharedContentKeys: Set<String>
    }

    /// Synchronous cache priming — no network. Seeds ``DetailPresentationCache`` from feed rows.
    static func primeFromCaches(
        messages: [Message],
        sharedTrades: inout [TradeID: Trade],
        sharedPosts: inout [PostID: Post],
        sharedReels: inout [ReelID: Reel],
        sharedAchievements: inout [AchievementID: Achievement],
        unavailableSharedContentKeys: inout Set<String>,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) {
        let references = unresolvedReferences(
            from: messages,
            sharedTrades: sharedTrades,
            sharedPosts: sharedPosts,
            sharedReels: sharedReels,
            sharedAchievements: sharedAchievements,
            unavailableSharedContentKeys: unavailableSharedContentKeys
        )

        var memoryHits = 0
        var feedHits = 0

        for reference in references {
            let (type, id) = probeIdentity(for: reference)
            probe.logResolve(type: type, id: id)

            if applyDetailCache(
                reference: reference,
                sharedTrades: &sharedTrades,
                sharedPosts: &sharedPosts,
                sharedReels: &sharedReels,
                sharedAchievements: &sharedAchievements,
                detailCache: context.detailCache
            ) {
                memoryHits += 1
                probe.logMemoryCacheHit(true)
                continue
            }
            probe.logMemoryCacheHit(false)

            if let viewerID = context.viewerID,
               let seed = context.feedSessionStore.lookup(reference: reference, viewerID: viewerID)
            {
                applyFeedSeed(
                    seed,
                    reference: reference,
                    sharedTrades: &sharedTrades,
                    sharedPosts: &sharedPosts,
                    sharedReels: &sharedReels,
                    sharedAchievements: &sharedAchievements,
                    detailCache: context.detailCache
                )
                feedHits += 1
                probe.logFeedCacheHit(true)
            } else {
                probe.logFeedCacheHit(false)
            }
        }

        primeTradeAttachmentCaches(
            from: messages,
            sharedTrades: &sharedTrades,
            detailCache: context.detailCache,
            feedSessionStore: context.feedSessionStore,
            viewerID: context.viewerID
        )

        probe.logSnapshotAvailable(memoryHits + feedHits > 0)
        if memoryHits + feedHits > 0 || hasRenderableContent(
            messages: messages,
            sharedTrades: sharedTrades,
            sharedPosts: sharedPosts,
            sharedReels: sharedReels,
            sharedAchievements: sharedAchievements,
            unavailableSharedContentKeys: unavailableSharedContentKeys
        ) {
            probe.markFirstRenderableIfNeeded()
        }
    }

    /// Network hydration for unresolved references — parallel per content type, batched trades + profiles.
    static func hydrateMissing(
        messages: [Message],
        snapshot: Snapshot,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> Snapshot {
        var sharedTrades = snapshot.sharedTrades
        var sharedPosts = snapshot.sharedPosts
        var sharedReels = snapshot.sharedReels
        var sharedAchievements = snapshot.sharedAchievements
        var unavailableSharedContentKeys = snapshot.unavailableSharedContentKeys

        let references = unresolvedReferences(
            from: messages,
            sharedTrades: sharedTrades,
            sharedPosts: sharedPosts,
            sharedReels: sharedReels,
            sharedAchievements: sharedAchievements,
            unavailableSharedContentKeys: unavailableSharedContentKeys
        )

        var pendingFeedPosts: [PostID] = []
        var pendingProfilePosts: [PostID] = []
        var pendingReels: [ReelID] = []
        var pendingAchievements: [AchievementID] = []

        for reference in references {
            switch reference {
            case .feedPost(let id):
                pendingFeedPosts.append(id)
            case .profilePost(let id):
                pendingProfilePosts.append(id)
            case .reel(let id):
                pendingReels.append(id)
            case .achievementPost(let id):
                pendingAchievements.append(AchievementID(id.rawValue))
            case .trade:
                break
            }
        }

        let pendingTradeIDs = missingTradeIDs(
            from: messages,
            sharedTrades: sharedTrades,
            sharedPosts: sharedPosts
        )

        probe.logHydrateBatch(
            trades: pendingTradeIDs.count,
            reels: pendingReels.count,
            posts: pendingFeedPosts.count + pendingProfilePosts.count,
            achievements: pendingAchievements.count
        )

        let batchStarted = CFAbsoluteTimeGetCurrent()

        await withTaskGroup(of: ParallelFetchResult?.self) { group in
            for id in Set(pendingFeedPosts) where sharedPosts[id] == nil {
                group.addTask {
                    await loadFeedPost(id: id, context: context, probe: probe)
                }
            }
            for id in Set(pendingProfilePosts) where sharedPosts[id] == nil {
                group.addTask {
                    await loadProfilePost(id: id, context: context, probe: probe)
                }
            }
            for id in Set(pendingReels) where sharedReels[id] == nil {
                group.addTask {
                    await loadReel(id: id, context: context, probe: probe)
                }
            }
            for id in Set(pendingAchievements) where sharedAchievements[id] == nil {
                group.addTask {
                    await loadAchievement(id: id, context: context, probe: probe)
                }
            }

            for await result in group {
                guard let result else { continue }
                switch result {
                case .post(let id, let post):
                    sharedPosts[id] = post
                    context.detailCache.seed(post)
                case .reel(let id, let reel, let embeddedTrade):
                    sharedReels[id] = reel
                    context.detailCache.seed(reel)
                    if let embeddedTrade {
                        context.detailCache.seed(embeddedTrade)
                        sharedTrades[embeddedTrade.id] = embeddedTrade
                    }
                case .achievement(let id, let achievement):
                    sharedAchievements[id] = achievement
                    context.detailCache.seed(achievement)
                case .unavailable(let key):
                    unavailableSharedContentKeys.insert(key)
                }
            }
        }

        if hasRenderableContent(
            messages: messages,
            sharedTrades: sharedTrades,
            sharedPosts: sharedPosts,
            sharedReels: sharedReels,
            sharedAchievements: sharedAchievements,
            unavailableSharedContentKeys: unavailableSharedContentKeys
        ) {
            probe.markFirstRenderableIfNeeded()
        }

        await fetchTrades(
            ids: missingTradeIDs(
                from: messages,
                sharedTrades: sharedTrades,
                sharedPosts: sharedPosts
            ),
            sharedTrades: &sharedTrades,
            unavailableSharedContentKeys: &unavailableSharedContentKeys,
            context: context,
            probe: probe
        )

        await hydrateAuthorProfiles(
            sharedPosts: sharedPosts,
            sharedReels: sharedReels,
            sharedAchievements: sharedAchievements,
            context: context
        )

        let batchMs = Int((CFAbsoluteTimeGetCurrent() - batchStarted) * 1000)
        probe.logBatchCompleted(dtMs: batchMs)
        probe.markAuthoritativeComplete()

        return Snapshot(
            sharedTrades: sharedTrades,
            sharedPosts: sharedPosts,
            sharedReels: sharedReels,
            sharedAchievements: sharedAchievements,
            unavailableSharedContentKeys: unavailableSharedContentKeys
        )
    }

    // MARK: - Reference collection

    private static func unresolvedReferences(
        from messages: [Message],
        sharedTrades: [TradeID: Trade],
        sharedPosts: [PostID: Post],
        sharedReels: [ReelID: Reel],
        sharedAchievements: [AchievementID: Achievement],
        unavailableSharedContentKeys: Set<String>
    ) -> [SharedContentReference] {
        messages.compactMap(\.sharedContent).filter { reference in
            guard !unavailableSharedContentKeys.contains(reference.stableKey) else { return false }
            switch reference {
            case .feedPost(let id), .profilePost(let id):
                return sharedPosts[id] == nil
            case .reel(let id):
                return sharedReels[id] == nil
            case .achievementPost(let id):
                return sharedAchievements[AchievementID(id.rawValue)] == nil
            case .trade(let id):
                return sharedTrades[id] == nil
            }
        }
    }

    private static func missingTradeIDs(
        from messages: [Message],
        sharedTrades: [TradeID: Trade],
        sharedPosts: [PostID: Post]
    ) -> [TradeID] {
        Array(
            Set(
                messages.compactMap { message -> TradeID? in
                    if let id = message.attachments.first?.tradeID, sharedTrades[id] == nil {
                        return id
                    }
                    if case .trade(let id) = message.sharedContent, sharedTrades[id] == nil {
                        return id
                    }
                    if let post = message.sharedContent.flatMap({ ref -> PostID? in
                        switch ref {
                        case .feedPost(let id): return id
                        default: return nil
                        }
                    }), let cached = sharedPosts[post], let tradeID = cached.linkedTradeID, sharedTrades[tradeID] == nil {
                        return tradeID
                    }
                    return nil
                }
            )
        )
    }

    private static func hasRenderableContent(
        messages: [Message],
        sharedTrades: [TradeID: Trade],
        sharedPosts: [PostID: Post],
        sharedReels: [ReelID: Reel],
        sharedAchievements: [AchievementID: Achievement],
        unavailableSharedContentKeys: Set<String>
    ) -> Bool {
        for message in messages {
            if let tradeID = message.attachments.first?.tradeID, sharedTrades[tradeID] != nil {
                return true
            }
            guard let reference = message.sharedContent else { continue }
            if unavailableSharedContentKeys.contains(reference.stableKey) { continue }
            switch reference {
            case .feedPost(let id), .profilePost(let id):
                if sharedPosts[id] != nil { return true }
            case .reel(let id):
                if sharedReels[id] != nil { return true }
            case .achievementPost(let id):
                if sharedAchievements[AchievementID(id.rawValue)] != nil { return true }
            case .trade(let id):
                if sharedTrades[id] != nil { return true }
            }
        }
        return false
    }

    // MARK: - Cache application

    private static func applyDetailCache(
        reference: SharedContentReference,
        sharedTrades: inout [TradeID: Trade],
        sharedPosts: inout [PostID: Post],
        sharedReels: inout [ReelID: Reel],
        sharedAchievements: inout [AchievementID: Achievement],
        detailCache: DetailPresentationCache
    ) -> Bool {
        switch reference {
        case .feedPost(let id), .profilePost(let id):
            guard let post = detailCache.post(id: id) else { return false }
            sharedPosts[id] = post
            if let tradeID = post.linkedTradeID, let trade = detailCache.trade(id: tradeID) {
                sharedTrades[tradeID] = trade
            }
            return true
        case .reel(let id):
            guard let reel = detailCache.reel(id: id) else { return false }
            sharedReels[id] = reel
            if let tradeID = reel.linkedTradeID, let trade = detailCache.trade(id: tradeID) {
                sharedTrades[tradeID] = trade
            }
            return true
        case .achievementPost(let id):
            let achievementID = AchievementID(id.rawValue)
            guard let achievement = detailCache.achievement(id: achievementID) else { return false }
            sharedAchievements[achievementID] = achievement
            return true
        case .trade(let id):
            guard let trade = detailCache.trade(id: id) else { return false }
            sharedTrades[id] = trade
            return true
        }
    }

    private static func applyFeedSeed(
        _ seed: FeedSessionStore.SharedContentSeed,
        reference: SharedContentReference,
        sharedTrades: inout [TradeID: Trade],
        sharedPosts: inout [PostID: Post],
        sharedReels: inout [ReelID: Reel],
        sharedAchievements: inout [AchievementID: Achievement],
        detailCache: DetailPresentationCache
    ) {
        FeedBootstrap.seedAuthor(from: seed.item, detailCache: detailCache)

        if let trade = seed.trade {
            detailCache.seed(trade)
            sharedTrades[trade.id] = trade
        }
        if let post = seed.post {
            detailCache.seed(post)
            sharedPosts[post.id] = post
        }
        if let reel = seed.reel {
            detailCache.seed(reel)
            sharedReels[reel.id] = reel
            if let tradeID = reel.linkedTradeID, let trade = detailCache.trade(id: tradeID) {
                sharedTrades[tradeID] = trade
            }
        }
        if let achievement = seed.achievement {
            detailCache.seed(achievement)
            sharedAchievements[achievement.id] = achievement
        }

        switch reference {
        case .feedPost(let id) where seed.post == nil && seed.trade != nil:
            sharedPosts[id] = seed.syntheticFeedPost
        default:
            break
        }
    }

    private static func primeTradeAttachmentCaches(
        from messages: [Message],
        sharedTrades: inout [TradeID: Trade],
        detailCache: DetailPresentationCache,
        feedSessionStore: FeedSessionStore,
        viewerID: ProfileID?
    ) {
        for message in messages {
            guard let tradeID = message.attachments.first?.tradeID, sharedTrades[tradeID] == nil else {
                continue
            }
            if let trade = detailCache.trade(id: tradeID) {
                sharedTrades[tradeID] = trade
                continue
            }
            if let viewerID,
               let seed = feedSessionStore.lookupTrade(id: tradeID, viewerID: viewerID)
            {
                detailCache.seed(seed)
                sharedTrades[tradeID] = seed
            }
        }
    }

    // MARK: - Network

    private static func loadFeedPost(
        id: PostID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let key = SharedContentReference.feedPost(id).stableKey
        guard let feedRepo = context.feedRepo else {
            return .unavailable(key)
        }
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "feedPost", count: 1)
        if let post = try? await feedRepo.post(id: id) {
            probe.logMetadataReturned(type: "feedPost", dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000))
            return .post(id, post)
        }
        return .unavailable(key)
    }

    private static func loadProfilePost(
        id: PostID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let key = SharedContentReference.profilePost(id).stableKey
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "profilePost", count: 1)
        if let post = try? await context.profilesRepo.wallPost(id: id) {
            probe.logMetadataReturned(type: "profilePost", dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000))
            return .post(id, post)
        }
        return .unavailable(key)
    }

    private static func loadReel(
        id: ReelID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let key = SharedContentReference.reel(id).stableKey
        guard let feedRepo = context.feedRepo else {
            return .unavailable(key)
        }
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "reel", count: 1)
        if let result = try? await feedRepo.reel(id: id) {
            probe.logMetadataReturned(type: "reel", dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000))
            return .reel(id, result.reel, embeddedTrade: result.embeddedTrade)
        }
        return .unavailable(key)
    }

    private static func loadAchievement(
        id: AchievementID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let key = SharedContentReference.achievementPost(PostID(id.rawValue)).stableKey
        guard let achievementsRepo = context.achievementsRepo else {
            return .unavailable(key)
        }
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "achievement", count: 1)
        if let achievement = try? await achievementsRepo.achievement(id: id) {
            probe.logMetadataReturned(type: "achievement", dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000))
            return .achievement(id, achievement)
        }
        return .unavailable(key)
    }

    private static func fetchTrades(
        ids: [TradeID],
        sharedTrades: inout [TradeID: Trade],
        unavailableSharedContentKeys: inout Set<String>,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async {
        let missing = ids.filter { sharedTrades[$0] == nil }
        guard !missing.isEmpty, let tradesRepo = context.tradesRepo else { return }
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "trade", count: missing.count)
        let fetched = (try? await SessionTradeEntityStore.shared.trades(
            ids: missing,
            detailCache: context.detailCache,
            repository: tradesRepo
        )) ?? []
        for trade in fetched {
            sharedTrades[trade.id] = trade
        }
        let notFound = Set(missing).subtracting(fetched.map(\.id))
        for id in notFound {
            unavailableSharedContentKeys.insert("trade:\(id.rawValue)")
        }
        probe.logMetadataReturned(type: "trade", dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000))
    }

    private static func hydrateAuthorProfiles(
        sharedPosts: [PostID: Post],
        sharedReels: [ReelID: Reel],
        sharedAchievements: [AchievementID: Achievement],
        context: Context
    ) async {
        var authorIDs: [ProfileID] = []
        authorIDs.append(contentsOf: sharedPosts.values.map(\.authorProfileID))
        authorIDs.append(contentsOf: sharedReels.values.map(\.authorProfileID))
        authorIDs.append(contentsOf: sharedAchievements.values.map(\.ownerProfileID))
        let missing = Array(Set(authorIDs)).filter { context.detailCache.profile(id: $0) == nil }
        guard !missing.isEmpty else { return }
        _ = try? await SessionProfileStore.shared.profiles(
            ids: missing,
            detailCache: context.detailCache,
            repository: context.profilesRepo
        )
    }

    private static func probeIdentity(for reference: SharedContentReference) -> (String, String) {
        switch reference {
        case .feedPost(let id): return ("feedPost", id.rawValue)
        case .profilePost(let id): return ("profilePost", id.rawValue)
        case .achievementPost(let id): return ("achievementPost", id.rawValue)
        case .reel(let id): return ("reel", id.rawValue)
        case .trade(let id): return ("trade", id.rawValue)
        }
    }
}
