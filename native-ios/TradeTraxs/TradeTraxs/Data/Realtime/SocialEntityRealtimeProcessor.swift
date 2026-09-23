import Foundation

/// Applies canonical social entity Realtime events to Feed + Profile presentation owners.
@MainActor
final class SocialEntityRealtimeProcessor {
    static let shared = SocialEntityRealtimeProcessor()

    struct FeedContext {
        var viewerID: ProfileID
        var scope: FeedScope
        var contentFilter: FeedContentFilter
        var trackedEntityIDsByTable: [SocialEntityRealtimeTable: Set<String>]
        var onInsert: (FeedTimelineEntry) -> Void
        var onUpdate: (FeedTimelineEntry) -> Void
        var onDelete: (String) -> Void
        var persistFirstPage: () -> Void
    }

    struct ProfileContext {
        var viewerID: ProfileID
        var profileID: ProfileID
        var onPatch: (SocialEntityRealtimeEvent) -> Void
        var onDelete: (SocialEntityRealtimeEvent) -> Void
    }

    private var feedContext: FeedContext?
    private var profileContext: ProfileContext?
    private var seenEventKeys: Set<String> = []
    private var tombstonedEntityKeys: Set<String> = []
    private let maxSeenKeys = 2_048

    private var feed: (any FeedRepository)?
    private var trades: (any TradeRepository)?
    private var profiles: (any ProfileRepository)?
    private var achievements: (any AchievementRepository)?
    private var detailCache: DetailPresentationCache?

    private init() {}

    func configure(
        feed: any FeedRepository,
        trades: any TradeRepository,
        profiles: any ProfileRepository,
        achievements: any AchievementRepository,
        detailCache: DetailPresentationCache
    ) {
        self.feed = feed
        self.trades = trades
        self.profiles = profiles
        self.achievements = achievements
        self.detailCache = detailCache
    }

    func bindFeed(_ context: FeedContext?) {
        feedContext = context
    }

    func bindProfile(_ context: ProfileContext?) {
        profileContext = context
    }

    func resetSession() {
        feedContext = nil
        profileContext = nil
        seenEventKeys.removeAll()
        tombstonedEntityKeys.removeAll()
        Task { await SocialEntitySummaryHydrationFlight.shared.reset() }
    }

    func handle(_ event: SocialEntityRealtimeEvent, viewerUserID: String) async {
        if let dedupe = event.eventRowID {
            let key = "\(event.table.rawValue):\(dedupe):\(event.mutation)"
            if seenEventKeys.contains(key) {
                #if DEBUG
                SocialEntityRealtimeDebugLog.duplicateIgnored(table: event.table.rawValue, id: event.entityID)
                #endif
                return
            }
            seenEventKeys.insert(key)
            if seenEventKeys.count > maxSeenKeys { seenEventKeys.removeAll(keepingCapacity: true) }
        }

        if let author = event.authorID, FeedBlockedAuthorsFilter.shared.contains(ProfileID(author)) {
            #if DEBUG
            SocialEntityRealtimeDebugLog.ignoredBlocked(authorID: author)
            #endif
            return
        }

        if let profileContext {
            await applyProfile(event, context: profileContext, viewerUserID: viewerUserID)
        }
        if let feedContext, feedContext.viewerID.rawValue == viewerUserID {
            await applyFeed(event, context: feedContext, viewerUserID: viewerUserID)
        }
    }

    // MARK: - Feed

    private func applyFeed(
        _ event: SocialEntityRealtimeEvent,
        context: FeedContext,
        viewerUserID: String
    ) async {
        switch event.mutation {
        case .delete:
            #if DEBUG
            SocialEntityRealtimeDebugLog.entityDelete(table: event.table.rawValue, id: event.entityID)
            #endif
            let entityKey = hydrationKey(table: event.table, entityID: event.entityID)
            tombstonedEntityKeys.insert(entityKey)
            _ = await SocialEntitySummaryHydrationFlight.shared.bumpGeneration(entityKey: entityKey)
            context.onDelete(event.entityID)
            FeedPersistedCacheCoordinator.removeEntry(viewerID: context.viewerID, entryID: event.entityID)
            removeSocialEntityDisk(event: event, viewerID: context.viewerID)
            context.persistFirstPage()
            #if DEBUG
            SocialEntityRealtimeDebugLog.feedPatch(id: event.entityID)
            SocialEntityRealtimeDebugLog.persist(table: event.table.rawValue, id: event.entityID)
            #endif
            return

        case .insert, .update:
            guard await feedScopeAllows(event, context: context, viewerUserID: viewerUserID) else {
                #if DEBUG
                SocialEntityRealtimeDebugLog.ignoredOutOfScope(
                    table: event.table.rawValue,
                    id: event.entityID,
                    reason: "feed_scope"
                )
                #endif
                return
            }
            guard contentFilterAllows(event, filter: context.contentFilter) else {
                #if DEBUG
                SocialEntityRealtimeDebugLog.ignoredOutOfScope(
                    table: event.table.rawValue,
                    id: event.entityID,
                    reason: "content_filter"
                )
                #endif
                return
            }
            if event.mutation == .update, event.payload.isPublic == false, event.table == .trades {
                #if DEBUG
                SocialEntityRealtimeDebugLog.visibilityRemove(table: event.table.rawValue, id: event.entityID)
                #endif
                context.onDelete(event.entityID)
                FeedPersistedCacheCoordinator.removeEntry(viewerID: context.viewerID, entryID: event.entityID)
                removeSocialEntityDisk(event: event, viewerID: context.viewerID)
                context.persistFirstPage()
                return
            }

            if event.mutation == .insert {
                #if DEBUG
                SocialEntityRealtimeDebugLog.entityInsert(table: event.table.rawValue, id: event.entityID)
                #endif
            } else {
                #if DEBUG
                SocialEntityRealtimeDebugLog.entityUpdate(table: event.table.rawValue, id: event.entityID)
                #endif
            }

            guard let entry = await hydrateFeedEntry(event, context: context) else { return }
            if event.mutation == .insert {
                context.onInsert(entry)
            } else {
                context.onUpdate(entry)
            }
            persistFeedEntity(entry, event: event, viewerID: context.viewerID)
            context.persistFirstPage()
            #if DEBUG
            SocialEntityRealtimeDebugLog.feedPatch(id: event.entityID)
            #endif
        }
    }

    private func feedScopeAllows(
        _ event: SocialEntityRealtimeEvent,
        context: FeedContext,
        viewerUserID: String
    ) async -> Bool {
        switch context.scope {
        case .global:
            if event.mutation == .insert {
                return false
            }
            return context.trackedEntityIDsByTable[event.table]?.contains(event.entityID) == true
        case .following:
            guard let author = event.authorID else { return false }
            if author == viewerUserID { return true }
            if let known = await SessionFollowingStore.shared.knownIsFollowing(
                viewerID: viewerUserID,
                targetID: author
            ) {
                return known
            }
            if await SessionFollowingStore.shared.isComplete(viewerID: viewerUserID),
               let set = await SessionFollowingStore.shared.cached(viewerID: viewerUserID)
            {
                return set.contains(author)
            }
            return event.mutation != .insert
        }
    }

    private func contentFilterAllows(_ event: SocialEntityRealtimeEvent, filter: FeedContentFilter) -> Bool {
        switch filter {
        case .all: return true
        case .trades: return event.table == .trades || event.table == .posts
        case .posts: return event.table == .profilePosts || event.table == .posts
        case .clips: return event.table == .reels
        case .achievements: return event.table == .achievementPosts
        }
    }

    private func hydrateFeedEntry(
        _ event: SocialEntityRealtimeEvent,
        context: FeedContext
    ) async -> FeedTimelineEntry? {
        let entityKey = hydrationKey(table: event.table, entityID: event.entityID)
        let generation = await SocialEntitySummaryHydrationFlight.shared.currentGeneration(entityKey: entityKey)
        let activeGeneration = generation == 0 ? 1 : generation

        #if DEBUG
        SocialEntityRealtimeDebugLog.summaryHydration(table: event.table.rawValue, id: event.entityID)
        #endif

        return await SocialEntitySummaryHydrationFlight.shared.hydrate(
            entityKey: entityKey,
            generation: activeGeneration
        ) { [weak self] in
            await self?.buildFeedEntry(event, viewerID: context.viewerID)
        }
    }

    private func buildFeedEntry(
        _ event: SocialEntityRealtimeEvent,
        viewerID: ProfileID
    ) async -> FeedTimelineEntry? {
        let entityKey = hydrationKey(table: event.table, entityID: event.entityID)
        if tombstonedEntityKeys.contains(entityKey) { return nil }
        guard let detailCache else { return nil }
        guard let item = feedItem(from: event) else { return nil }
        FeedBootstrap.seedAuthor(from: item, detailCache: detailCache)
        if let entry = FeedBootstrap.buildEntryFromItemSync(item, detailCache: detailCache) {
            return entry
        }
        guard let feed, let trades, let profiles, let achievements else { return nil }
        return await FeedBootstrap.hydrateOne(
            item,
            feed: feed,
            trades: trades,
            profiles: profiles,
            achievements: achievements,
            detailCache: detailCache
        )
    }

    private func feedItem(from event: SocialEntityRealtimeEvent) -> FeedItem? {
        guard let authorRaw = event.authorID else { return nil }
        let author = ProfileID(authorRaw)
        let created = event.payload.createdAt ?? Date()
        switch event.table {
        case .posts:
            let postID = PostID(event.entityID)
            let tradeID = event.payload.tradeID.map { TradeID($0) }
            let kind: FeedItemKind = tradeID == nil ? .post : .trade
            return FeedItem(
                id: event.entityID,
                kind: kind,
                authorProfileID: author,
                createdAt: created,
                tradeID: tradeID,
                postID: postID,
                reelID: nil,
                storyID: nil,
                achievementID: nil,
                caption: event.payload.caption,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false,
                mediaURL: event.payload.mediaURL,
                engagementStateCached: false
            )
        case .profilePosts:
            return FeedItem(
                id: event.entityID,
                kind: .post,
                authorProfileID: author,
                createdAt: created,
                tradeID: nil,
                postID: PostID(event.entityID),
                reelID: nil,
                storyID: nil,
                achievementID: nil,
                caption: event.payload.caption,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false,
                mediaURL: event.payload.mediaURL,
                engagementStateCached: false
            )
        case .trades:
            return FeedItem(
                id: event.entityID,
                kind: .trade,
                authorProfileID: author,
                createdAt: created,
                tradeID: TradeID(event.entityID),
                postID: nil,
                reelID: nil,
                storyID: nil,
                achievementID: nil,
                caption: event.payload.caption,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false,
                engagementStateCached: false
            )
        case .reels:
            return FeedItem(
                id: event.entityID,
                kind: .reel,
                authorProfileID: author,
                createdAt: created,
                tradeID: nil,
                postID: nil,
                reelID: ReelID(event.entityID),
                storyID: nil,
                achievementID: nil,
                caption: event.payload.caption,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false,
                mediaURL: event.payload.mediaURL,
                engagementStateCached: false
            )
        case .achievementPosts:
            let achID = event.payload.achievementID ?? event.entityID
            return FeedItem(
                id: event.entityID,
                kind: .achievement,
                authorProfileID: author,
                createdAt: created,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                storyID: nil,
                achievementID: AchievementID(achID),
                caption: event.payload.caption,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false,
                mediaURL: event.payload.mediaURL,
                engagementStateCached: false
            )
        }
    }

    private func persistFeedEntity(
        _ entry: FeedTimelineEntry,
        event: SocialEntityRealtimeEvent,
        viewerID: ProfileID
    ) {
        switch entry {
        case .trade(_, let summary):
            SocialEntityPersistedCacheCoordinator.saveTradeSummary(
                summary,
                viewerID: viewerID,
                source: .feed,
                mergeMode: .merge
            )
        case .post(_, let post):
            SocialEntityPersistedCacheCoordinator.savePost(post, viewerID: viewerID, source: .feed)
        case .clip(_, let reel):
            SocialEntityPersistedCacheCoordinator.saveReel(reel, viewerID: viewerID, source: .feed)
        case .achievement(_, let achievement):
            SocialEntityPersistedCacheCoordinator.saveAchievement(
                achievement,
                viewerID: viewerID,
                source: .feed
            )
        }
        #if DEBUG
        SocialEntityRealtimeDebugLog.persist(table: event.table.rawValue, id: event.entityID)
        #endif
    }

    private func removeSocialEntityDisk(event: SocialEntityRealtimeEvent, viewerID: ProfileID) {
        switch event.table {
        case .posts, .profilePosts:
            SocialEntityDiskCache.removePost(id: PostID(event.entityID), viewerID: viewerID)
        case .trades:
            SocialEntityDiskCache.removeTrade(id: TradeID(event.entityID), viewerID: viewerID)
        case .reels:
            SocialEntityDiskCache.removeReel(id: ReelID(event.entityID), viewerID: viewerID)
        case .achievementPosts:
            SocialEntityDiskCache.removeAchievement(id: AchievementID(event.entityID), viewerID: viewerID)
        }
    }

    // MARK: - Profile

    private func applyProfile(
        _ event: SocialEntityRealtimeEvent,
        context: ProfileContext,
        viewerUserID: String
    ) async {
        guard event.authorID == context.profileID.rawValue else { return }

        switch event.mutation {
        case .delete:
            #if DEBUG
            SocialEntityRealtimeDebugLog.entityDelete(table: event.table.rawValue, id: event.entityID)
            #endif
            let entityKey = hydrationKey(table: event.table, entityID: event.entityID)
            _ = await SocialEntitySummaryHydrationFlight.shared.bumpGeneration(entityKey: entityKey)
            context.onDelete(event)
            removeSocialEntityDisk(event: event, viewerID: context.viewerID)
            #if DEBUG
            SocialEntityRealtimeDebugLog.profilePatch(profileID: context.profileID.rawValue, id: event.entityID)
            #endif
        case .insert, .update:
            if event.mutation == .insert {
                #if DEBUG
                SocialEntityRealtimeDebugLog.entityInsert(table: event.table.rawValue, id: event.entityID)
                #endif
            } else {
                #if DEBUG
                SocialEntityRealtimeDebugLog.entityUpdate(table: event.table.rawValue, id: event.entityID)
                #endif
            }
            context.onPatch(event)
            #if DEBUG
            SocialEntityRealtimeDebugLog.profilePatch(profileID: context.profileID.rawValue, id: event.entityID)
            #endif
        }
    }

    private func hydrationKey(table: SocialEntityRealtimeTable, entityID: String) -> String {
        "\(table.rawValue):\(entityID)"
    }
}
