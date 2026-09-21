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
        var diskHits = 0

        for reference in references {
            let (type, id) = probeIdentity(for: reference)

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
                probe.logResolution(type: type, contentID: id, source: "memory", result: "resolved")
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
                probe.logResolution(type: type, contentID: id, source: "feedCache", result: "resolved")
                continue
            }
            probe.logFeedCacheHit(false)

            if let viewerID = context.viewerID,
               applyDiskCache(
                   reference: reference,
                   viewerID: viewerID,
                   sharedTrades: &sharedTrades,
                   sharedPosts: &sharedPosts,
                   sharedReels: &sharedReels,
                   sharedAchievements: &sharedAchievements,
                   detailCache: context.detailCache
               )
            {
                diskHits += 1
                probe.logResolution(type: type, contentID: id, source: "disk", result: "resolved")
            }
        }

        primeTradeAttachmentCaches(
            from: messages,
            sharedTrades: &sharedTrades,
            detailCache: context.detailCache,
            feedSessionStore: context.feedSessionStore,
            viewerID: context.viewerID
        )

        probe.logSnapshotAvailable(memoryHits + feedHits + diskHits > 0)
        if memoryHits + feedHits + diskHits > 0 || hasRenderableContent(
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

        var pendingFeedPosts = Set<PostID>()
        var pendingProfilePosts = Set<PostID>()
        var pendingReels = Set<ReelID>()
        var pendingAchievements = Set<AchievementID>()

        for reference in references {
            switch reference {
            case .feedPost(let id):
                pendingFeedPosts.insert(id)
            case .profilePost(let id):
                pendingProfilePosts.insert(id)
            case .reel(let id):
                pendingReels.insert(id)
            case .achievementPost(let id):
                pendingAchievements.insert(AchievementID(id.rawValue))
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
            for id in pendingFeedPosts where sharedPosts[id] == nil {
                group.addTask {
                    await loadFeedPost(id: id, context: context, probe: probe)
                }
            }
            for id in pendingProfilePosts where sharedPosts[id] == nil {
                group.addTask {
                    await loadProfilePost(id: id, context: context, probe: probe)
                }
            }
            for id in pendingReels where sharedReels[id] == nil {
                group.addTask {
                    await loadReel(id: id, context: context, probe: probe)
                }
            }
            for id in pendingAchievements where sharedAchievements[id] == nil {
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
                    probe.logResolution(
                        type: keyPrefix(key),
                        contentID: keySuffix(key),
                        source: "network",
                        result: "unavailable",
                        reason: "notFound"
                    )
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

    private static func applyDiskCache(
        reference: SharedContentReference,
        viewerID: ProfileID,
        sharedTrades: inout [TradeID: Trade],
        sharedPosts: inout [PostID: Post],
        sharedReels: inout [ReelID: Reel],
        sharedAchievements: inout [AchievementID: Achievement],
        detailCache: DetailPresentationCache
    ) -> Bool {
        switch reference {
        case .feedPost(let id), .profilePost(let id):
            guard let post = SocialEntityDiskCache.loadPost(id: id, viewerID: viewerID) else { return false }
            detailCache.seed(post)
            sharedPosts[id] = post
            if let tradeID = post.linkedTradeID,
               let summary = SocialEntityDiskCache.loadTradeSummary(id: tradeID, viewerID: viewerID)
            {
                detailCache.seedPresentationSeed(summary)
                sharedTrades[tradeID] = TradeSummaryMapper.previewTrade(from: summary)
            }
            return true
        case .reel(let id):
            guard let reel = SocialEntityDiskCache.loadReel(id: id, viewerID: viewerID) else { return false }
            detailCache.seed(reel)
            sharedReels[id] = reel
            if let tradeID = reel.linkedTradeID,
               let summary = SocialEntityDiskCache.loadTradeSummary(id: tradeID, viewerID: viewerID)
            {
                detailCache.seedPresentationSeed(summary)
                sharedTrades[tradeID] = TradeSummaryMapper.previewTrade(from: summary)
            }
            return true
        case .achievementPost(let id):
            let achievementID = AchievementID(id.rawValue)
            guard let achievement = SocialEntityDiskCache.loadAchievement(id: achievementID, viewerID: viewerID)
            else { return false }
            detailCache.seed(achievement)
            sharedAchievements[achievementID] = achievement
            return true
        case .trade(let id):
            guard let summary = SocialEntityDiskCache.loadTradeSummary(id: id, viewerID: viewerID) else { return false }
            detailCache.seedPresentationSeed(summary)
            sharedTrades[id] = TradeSummaryMapper.previewTrade(from: summary)
            return true
        }
    }

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
            if let tradeID = post.linkedTradeID,
               let preview = detailCache.previewTrade(id: tradeID)
                ?? detailCache.tradeSummary(id: tradeID).map({ TradeSummaryMapper.previewTrade(from: $0) })
            {
                sharedTrades[tradeID] = preview
            }
            return true
        case .reel(let id):
            guard let reel = detailCache.reel(id: id) else { return false }
            sharedReels[id] = reel
            if let tradeID = reel.linkedTradeID,
               let preview = detailCache.previewTrade(id: tradeID)
                ?? detailCache.tradeSummary(id: tradeID).map({ TradeSummaryMapper.previewTrade(from: $0) })
            {
                sharedTrades[tradeID] = preview
            }
            return true
        case .achievementPost(let id):
            let achievementID = AchievementID(id.rawValue)
            guard let achievement = detailCache.achievement(id: achievementID) else { return false }
            sharedAchievements[achievementID] = achievement
            return true
        case .trade(let id):
            guard let preview = detailCache.previewTrade(id: id)
                ?? detailCache.tradeSummary(id: id).map({ TradeSummaryMapper.previewTrade(from: $0) })
            else { return false }
            sharedTrades[id] = preview
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

        if let summary = seed.tradeSummary {
            detailCache.seedPresentationSeed(DetailPresentationSeed(summary: summary))
            sharedTrades[summary.id] = TradeSummaryMapper.previewTrade(from: summary)
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
        case .feedPost(let id) where seed.post == nil && seed.tradeSummary != nil:
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
               let summary = feedSessionStore.lookupTradeSummary(id: tradeID, viewerID: viewerID)
            {
                detailCache.seedPresentationSeed(DetailPresentationSeed(summary: summary))
                sharedTrades[tradeID] = TradeSummaryMapper.previewTrade(from: summary)
            }
        }
    }

    // MARK: - Network

    private static func loadFeedPost(
        id: PostID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let stableKey = SharedContentReference.feedPost(id).stableKey
        guard let feedRepo = context.feedRepo else {
            probe.logResolution(type: "post", contentID: id.rawValue, source: "network", result: "failed", reason: "missingRepository")
            return .unavailable(stableKey)
        }
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "feedPost", count: 1)
        let flightKey = "sharedContent:feedPost:\(id.rawValue)"
        let coalesced = try? await RepositoryRequestFlight.shared.coalesceWithMetadata(
            key: flightKey,
            resource: "sharedContent.feedPost"
        ) {
            try await feedRepo.post(id: id)
        }
        guard let coalesced else {
            probe.logResolution(
                type: "post",
                contentID: id.rawValue,
                source: "network",
                result: "failed",
                durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000),
                reason: "networkFailure"
            )
            return .unavailable(stableKey)
        }
        let dtMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        probe.logMetadataReturned(type: "feedPost", dtMs: dtMs)
        probe.logResolution(
            type: "post",
            contentID: id.rawValue,
            source: "network",
            result: "resolved",
            durationMs: dtMs,
            deduped: coalesced.deduped
        )
        return .post(id, coalesced.value)
    }

    private static func loadProfilePost(
        id: PostID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let stableKey = SharedContentReference.profilePost(id).stableKey
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "profilePost", count: 1)
        let flightKey = "sharedContent:profilePost:\(id.rawValue)"
        let coalesced = try? await RepositoryRequestFlight.shared.coalesceWithMetadata(
            key: flightKey,
            resource: "sharedContent.profilePost"
        ) {
            try await context.profilesRepo.wallPost(id: id)
        }
        guard let coalesced else {
            probe.logResolution(
                type: "post",
                contentID: id.rawValue,
                source: "network",
                result: "failed",
                durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000),
                reason: "networkFailure"
            )
            return .unavailable(stableKey)
        }
        let dtMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        probe.logMetadataReturned(type: "profilePost", dtMs: dtMs)
        probe.logResolution(
            type: "post",
            contentID: id.rawValue,
            source: "network",
            result: "resolved",
            durationMs: dtMs,
            deduped: coalesced.deduped
        )
        return .post(id, coalesced.value)
    }

    private static func loadReel(
        id: ReelID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let stableKey = SharedContentReference.reel(id).stableKey
        guard let feedRepo = context.feedRepo else {
            return .unavailable(stableKey)
        }
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "reel", count: 1)
        let flightKey = "sharedContent:reel:\(id.rawValue)"
        let coalesced = try? await RepositoryRequestFlight.shared.coalesceWithMetadata(
            key: flightKey,
            resource: "sharedContent.reel"
        ) {
            try await feedRepo.reel(id: id)
        }
        guard let coalesced else {
            probe.logResolution(
                type: "reel",
                contentID: id.rawValue,
                source: "network",
                result: "failed",
                durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000),
                reason: "networkFailure"
            )
            return .unavailable(stableKey)
        }
        let dtMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        probe.logMetadataReturned(type: "reel", dtMs: dtMs)
        probe.logResolution(
            type: "reel",
            contentID: id.rawValue,
            source: "network",
            result: "resolved",
            durationMs: dtMs,
            deduped: coalesced.deduped
        )
        return .reel(id, coalesced.value.reel, embeddedTrade: coalesced.value.embeddedTrade)
    }

    private static func loadAchievement(
        id: AchievementID,
        context: Context,
        probe: SharedContentHydrationProbe.Session
    ) async -> ParallelFetchResult? {
        let stableKey = SharedContentReference.achievementPost(PostID(id.rawValue)).stableKey
        guard let achievementsRepo = context.achievementsRepo else {
            return .unavailable(stableKey)
        }
        let started = CFAbsoluteTimeGetCurrent()
        probe.logMetadataRequestStarted(type: "achievement", count: 1)
        let flightKey = "sharedContent:achievement:\(id.rawValue)"
        let coalesced = try? await RepositoryRequestFlight.shared.coalesceWithMetadata(
            key: flightKey,
            resource: "sharedContent.achievement"
        ) {
            try await achievementsRepo.achievement(id: id)
        }
        guard let coalesced else {
            probe.logResolution(
                type: "achievement",
                contentID: id.rawValue,
                source: "network",
                result: "failed",
                durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000),
                reason: "networkFailure"
            )
            return .unavailable(stableKey)
        }
        let dtMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        probe.logMetadataReturned(type: "achievement", dtMs: dtMs)
        probe.logResolution(
            type: "achievement",
            contentID: id.rawValue,
            source: "network",
            result: "resolved",
            durationMs: dtMs,
            deduped: coalesced.deduped
        )
        return .achievement(id, coalesced.value)
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
        case .feedPost(let id): return ("post", id.rawValue)
        case .profilePost(let id): return ("post", id.rawValue)
        case .achievementPost(let id): return ("achievement", id.rawValue)
        case .reel(let id): return ("reel", id.rawValue)
        case .trade(let id): return ("trade", id.rawValue)
        }
    }

    private static func keyPrefix(_ stableKey: String) -> String {
        stableKey.split(separator: ":", maxSplits: 1).first.map(String.init) ?? stableKey
    }

    private static func keySuffix(_ stableKey: String) -> String {
        stableKey.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? stableKey
    }
}
