import Foundation

/// Central write-through for viewer-scoped Profile disk snapshots + shared entity patches.
@MainActor
enum ProfilePersistedCacheCoordinator {
    // MARK: - Hydrate

    @discardableResult
    static func hydrate(
        viewerID: ProfileID,
        targetProfileID: ProfileID,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        blockedPeers: Set<ProfileID> = []
    ) -> ProfileState? {
        guard !blockedPeers.contains(targetProfileID) else { return nil }

        if let memory = ProfileSessionStore.shared.restore(
            viewerID: viewerID,
            targetProfileID: targetProfileID
        ), memory.profile != nil {
            seedCaches(
                from: memory,
                viewerID: viewerID,
                detailCache: detailCache,
                engagementStore: engagementStore
            )
            return memory
        }

        guard let blob = ProfileDiskCache.loadSnapshot(
            viewerID: viewerID,
            targetProfileID: targetProfileID
        ) else { return nil }

        let state = mapBlobToState(blob)
        ProfileSessionStore.shared.save(
            viewerID: viewerID,
            targetProfileID: targetProfileID,
            state: state
        )
        seedCaches(
            from: state,
            viewerID: viewerID,
            detailCache: detailCache,
            engagementStore: engagementStore
        )
        return state
    }

    /// Owner Profile — reuse session owner trades when header is already warm.
    static func hydrateOwnerTradesIfNeeded(
        ownerID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> [Trade]? {
        _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: ownerID,
            detailCache: detailCache
        )
        return SessionOwnerTradesStore.shared.cached(for: ownerID)
    }

    // MARK: - Persist

    static func persist(
        viewerID: ProfileID,
        targetProfileID: ProfileID,
        state: ProfileState,
        engagementStore: EngagementStore? = nil
    ) {
        var snapshot = state
        if let engagementStore, snapshot.didLoadTrades {
            snapshot.trades = syncTradeEngagement(into: snapshot.trades, engagementStore: engagementStore)
        }
        ProfileSessionStore.shared.save(
            viewerID: viewerID,
            targetProfileID: targetProfileID,
            state: snapshot
        )
        ProfileDiskCache.saveSnapshot(mapStateToBlob(viewerID: viewerID, targetProfileID: targetProfileID, state: snapshot))
    }

    // MARK: - Patch / prune

    static func patchTrade(_ trade: Trade, viewerID: ProfileID) {
        let summary = TradeSummaryMapper.summary(fromPartialListTrade: trade)
        let ownerID = trade.ownerProfileID
        if trade.visibility != .public {
            SocialEntityPersistedCacheCoordinator.removeTrade(id: trade.id, viewerID: viewerID)
        } else {
            SocialEntityPersistedCacheCoordinator.saveTradeSummary(
                summary,
                viewerID: viewerID,
                source: .mutation,
                mergeMode: .merge
            )
        }

        if var state = ProfileSessionStore.shared.restore(
            viewerID: viewerID,
            targetProfileID: ownerID
        ) {
            upsertTradeSummary(summary, trade: trade, into: &state.trades)
            persist(viewerID: viewerID, targetProfileID: ownerID, state: state)
        }

        for blob in ProfileDiskCache.allSnapshots(for: viewerID)
            where blob.targetProfileID == ownerID.rawValue
        {
            var state = mapBlobToState(blob)
            upsertTradeSummary(summary, trade: trade, into: &state.trades)
            persist(viewerID: viewerID, targetProfileID: ownerID, state: state)
        }
    }

    private static func upsertTradeSummary(
        _ summary: TradeSummary,
        trade: Trade,
        into trades: inout [TradeSummary]
    ) {
        if let index = trades.firstIndex(where: { $0.id == trade.id }) {
            trades[index] = summary
        } else if trade.visibility == .public {
            trades.insert(summary, at: 0)
        }
        trades = Array(trades.prefix(ProfileDiskCache.maxTradesPerProfile))
    }

    static func removeTrade(id: TradeID, owner: ProfileID, viewerID: ProfileID) {
        SocialEntityPersistedCacheCoordinator.removeTrade(id: id, viewerID: viewerID)
        for blob in ProfileDiskCache.allSnapshots(for: viewerID)
            where blob.targetProfileID == owner.rawValue
        {
            var state = mapBlobToState(blob)
            guard state.trades.contains(where: { $0.id == id }) else { continue }
            state.trades.removeAll { $0.id == id }
            persist(viewerID: viewerID, targetProfileID: owner, state: state)
        }
    }

    static func patchPost(_ post: Post, viewerID: ProfileID) {
        SocialEntityPersistedCacheCoordinator.savePost(
            post,
            viewerID: viewerID,
            source: .mutation,
            mergeMode: .merge
        )
        patchSectionItem(
            viewerID: viewerID,
            ownerID: post.authorProfileID,
            match: { (item: Post) in item.id == post.id },
            upsert: post,
            section: \.posts,
            didLoad: \.didLoadPosts,
            cap: ProfileDiskCache.maxPostsPerProfile
        )
    }

    static func removePost(id: PostID, owner: ProfileID, viewerID: ProfileID) {
        SocialEntityPersistedCacheCoordinator.removePost(id: id, viewerID: viewerID)
        removeSectionItem(
            viewerID: viewerID,
            ownerID: owner,
            match: { (item: Post) in item.id == id },
            section: \.posts
        )
    }

    static func patchReel(_ reel: Reel, viewerID: ProfileID) {
        SocialEntityPersistedCacheCoordinator.saveReel(
            reel,
            viewerID: viewerID,
            source: .mutation,
            mergeMode: .merge
        )
        patchSectionItem(
            viewerID: viewerID,
            ownerID: reel.authorProfileID,
            match: { (item: Reel) in item.id == reel.id },
            upsert: reel,
            section: \.clips,
            didLoad: \.didLoadClips,
            cap: ProfileDiskCache.maxClipsPerProfile
        )
    }

    static func removeReel(id: ReelID, owner: ProfileID, viewerID: ProfileID) {
        SocialEntityPersistedCacheCoordinator.removeReel(id: id, viewerID: viewerID)
        removeSectionItem(
            viewerID: viewerID,
            ownerID: owner,
            match: { (item: Reel) in item.id == id },
            section: \.clips
        )
    }

    /// Phase 9 — authoritative Profile → Clips tab load (lazy section; not in Stage-1 bootstrap).
    static func persistClipsSection(
        viewerID: ProfileID,
        targetProfileID: ProfileID,
        clips: [Reel],
        engagementStore: EngagementStore? = nil
    ) {
        guard var state = ProfileSessionStore.shared.restore(
            viewerID: viewerID,
            targetProfileID: targetProfileID
        ) ?? ProfileDiskCache.loadSnapshot(viewerID: viewerID, targetProfileID: targetProfileID)
            .map(mapBlobToState)
        else { return }
        state.clips = Array(clips.prefix(ProfileDiskCache.maxClipsPerProfile))
        state.didLoadClips = true
        persist(
            viewerID: viewerID,
            targetProfileID: targetProfileID,
            state: state,
            engagementStore: engagementStore
        )
        for reel in state.clips {
            SocialEntityPersistedCacheCoordinator.saveReel(
                reel,
                viewerID: viewerID,
                source: .profile,
                mergeMode: .replace
            )
        }
    }

    static func patchAchievement(_ achievement: Achievement, viewerID: ProfileID) {
        SocialEntityPersistedCacheCoordinator.saveAchievement(
            achievement,
            viewerID: viewerID,
            source: .mutation,
            mergeMode: .merge
        )
        patchSectionItem(
            viewerID: viewerID,
            ownerID: achievement.ownerProfileID,
            match: { (item: Achievement) in item.id == achievement.id },
            upsert: achievement,
            section: \.achievements,
            didLoad: \.didLoadAchievements,
            cap: ProfileDiskCache.maxAchievementsPerProfile
        )
    }

    static func patchProfileHeader(
        viewerID: ProfileID,
        targetProfileID: ProfileID,
        isFollowing: Bool?,
        isRequested: Bool? = nil,
        stats: ProfileStats?
    ) {
        guard var state = ProfileSessionStore.shared.restore(
            viewerID: viewerID,
            targetProfileID: targetProfileID
        ) ?? ProfileDiskCache.loadSnapshot(viewerID: viewerID, targetProfileID: targetProfileID)
            .map(mapBlobToState)
        else { return }
        if let isFollowing, !state.isOwner {
            state.isFollowing = isFollowing
        }
        if let isRequested, !state.isOwner {
            state.isRequested = isRequested
        }
        if let stats {
            state.stats = stats
        }
        persist(viewerID: viewerID, targetProfileID: targetProfileID, state: state)
    }

    static func pruneBlockedPeer(_ peerID: ProfileID) {
        ProfileDiskCache.removeSnapshotsForBlockedPeer(peerID)
    }

    static func clear(viewerID: ProfileID) {
        ProfileDiskCache.clear(viewerID: viewerID)
        ProfileSessionStore.shared.invalidate(viewerID: viewerID)
        SocialEntityPersistedCacheCoordinator.clear(viewerID: viewerID)
    }

    static func clearAll() {
        ProfileDiskCache.clearAll()
        ProfileSessionStore.shared.invalidate()
        SocialEntityPersistedCacheCoordinator.clearAll()
    }

    // MARK: - Mapping

    private static func mapBlobToState(_ blob: ProfileDiskCache.SnapshotBlob) -> ProfileState {
        var state = ProfileState()
        state.phase = .loaded
        state.profileID = ProfileID(blob.targetProfileID)
        state.profile = blob.profile
        state.stats = blob.stats
        state.isOwner = blob.isOwner
        state.isFollowing = blob.isFollowing
        state.isRequested = blob.isRequested
        state.followsYou = blob.followsYou
        state.canViewTrades = blob.canViewTrades
        state.ownedTradeRoom = blob.ownedTradeRoom
        state.didResolveTradeRoom = blob.didResolveTradeRoom
        state.activeStories = blob.activeStories
        state.pinnedContent = blob.pinnedContent
        state.trades = blob.trades
        state.tradesNextCursor = blob.tradesNextCursor
        state.accountNames = blob.accountNames.reduce(into: [:]) { result, entry in
            result[TradingAccountID(entry.key)] = entry.value
        }
        state.accountModes = blob.accountModes.reduce(into: [:]) { result, entry in
            if let mode = TradingAccountMode.parseWireValue(entry.value) {
                result[TradingAccountID(entry.key)] = mode
            }
        }
        state.accountSizes = blob.accountSizes.reduce(into: [:]) { result, entry in
            if let size = Decimal(string: entry.value) {
                result[TradingAccountID(entry.key)] = size
            }
        }
        state.posts = blob.posts
        state.clips = blob.clips
        state.achievements = blob.achievements
        state.didBootstrap = true
        state.didLoadTrades = blob.didLoadTrades
        state.didLoadPosts = blob.didLoadPosts
        state.didLoadClips = blob.didLoadClips
        state.didLoadAchievements = blob.didLoadAchievements
        state.engagementPresentation = blob.engagementPresentation
        state.lastUpdated = blob.savedAt
        return state
    }

    private static func mapStateToBlob(
        viewerID: ProfileID,
        targetProfileID: ProfileID,
        state: ProfileState
    ) -> ProfileDiskCache.SnapshotBlob {
        ProfileDiskCache.SnapshotBlob(
            viewerID: viewerID.rawValue,
            targetProfileID: targetProfileID.rawValue,
            savedAt: Date(),
            lastAccessedAt: Date(),
            profile: state.profile ?? Profile(
                id: targetProfileID,
                userID: UserID(targetProfileID.rawValue),
                username: "",
                displayName: "",
                bio: nil,
                avatar: nil,
                traderType: .futures,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: .now
            ),
            stats: state.stats,
            isOwner: state.isOwner,
            isFollowing: state.isFollowing,
            isRequested: state.isRequested,
            followsYou: state.followsYou,
            canViewTrades: state.canViewTrades,
            ownedTradeRoom: state.ownedTradeRoom,
            didResolveTradeRoom: state.didResolveTradeRoom,
            activeStories: state.activeStories,
            pinnedContent: state.pinnedContent,
            trades: state.trades,
            tradesNextCursor: state.tradesNextCursor,
            accountNames: Dictionary(
                uniqueKeysWithValues: state.accountNames.map { ($0.key.rawValue, $0.value) }
            ),
            accountModes: Dictionary(
                uniqueKeysWithValues: state.accountModes.map { ($0.key.rawValue, $0.value.rawValue) }
            ),
            accountSizes: Dictionary(
                uniqueKeysWithValues: state.accountSizes.map { ($0.key.rawValue, "\($0.value)") }
            ),
            posts: state.posts,
            clips: state.clips,
            achievements: state.achievements,
            didLoadTrades: state.didLoadTrades,
            didLoadPosts: state.didLoadPosts,
            didLoadClips: state.didLoadClips,
            didLoadAchievements: state.didLoadAchievements,
            engagementPresentation: state.engagementPresentation
        )
    }

    /// Patches presentation engagement on cached Profile snapshots when the target row is already present.
    @discardableResult
    static func patchEngagementPresentation(
        viewerID: ProfileID,
        target: InteractionTarget,
        snapshot: EngagementSnapshot,
        writeGeneration: UInt64
    ) -> Int {
        guard !SocialPresentationWriteThroughGeneration.isStale(
            viewerID: viewerID,
            target: target,
            generation: writeGeneration
        ) else { return 0 }

        var patched = 0
        var touchedProfileIDs = Set<String>()

        for profileID in ProfileSessionStore.shared.profileIDs(viewerID: viewerID) {
                guard var state = ProfileSessionStore.shared.restore(
                    viewerID: viewerID,
                    targetProfileID: profileID
                ), SocialPresentationTargetMatching.profileContains(target: target, state: state)
                else { continue }
                state.engagementPresentation[target.presentationStorageKey] = snapshot
                persist(viewerID: viewerID, targetProfileID: profileID, state: state)
                touchedProfileIDs.insert(profileID.rawValue)
                patched += 1
        }

        for blob in ProfileDiskCache.allSnapshots(for: viewerID) {
            guard !touchedProfileIDs.contains(blob.targetProfileID) else { continue }
            var state = mapBlobToState(blob)
            guard SocialPresentationTargetMatching.profileContains(target: target, state: state) else {
                continue
            }
            state.engagementPresentation[target.presentationStorageKey] = snapshot
            persist(
                viewerID: viewerID,
                targetProfileID: ProfileID(blob.targetProfileID),
                state: state
            )
            patched += 1
        }

        return patched
    }

    private static func seedCaches(
        from state: ProfileState,
        viewerID: ProfileID,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore?
    ) {
        guard let profileID = state.profileID ?? state.profile?.id else { return }
        if let profile = state.profile {
            detailCache.seed(profile)
            SocialEntityPersistedCacheCoordinator.saveProfile(
                profile,
                viewerID: viewerID,
                source: .profile,
                mergeMode: .replace
            )
        }
        if let stats = state.stats {
            detailCache.seed(stats: stats)
        }
        if let room = state.ownedTradeRoom {
            detailCache.seedOwnedTradeRoom(room, for: profileID)
        }
        if !state.isOwner {
            detailCache.setViewerFollows(profileID, isFollowing: state.isFollowing)
        }
        detailCache.seed(publicTradeSummaries: state.trades, for: profileID)
        detailCache.seedPublicAccountMetadata(
            names: state.accountNames,
            modes: state.accountModes,
            sizes: state.accountSizes,
            for: profileID
        )
        detailCache.seed(posts: state.posts)
        detailCache.seed(reels: state.clips)
        for achievement in state.achievements {
            detailCache.seed(achievement)
        }
        for story in state.activeStories {
            detailCache.seed(story)
        }
        for (key, snap) in state.engagementPresentation {
            guard let target = InteractionTarget(presentationStorageKey: key) else { continue }
            engagementStore?.seed(snap, for: target)
        }
        for summary in state.trades {
            _ = engagementStore?.snapshot(for: .trade(summary.id))
            SocialEntityPersistedCacheCoordinator.saveTradeSummary(
                summary,
                viewerID: viewerID,
                source: .profile,
                mergeMode: .replace
            )
        }
        for post in state.posts {
            SocialEntityPersistedCacheCoordinator.savePost(
                post,
                viewerID: viewerID,
                source: .profile,
                mergeMode: .replace
            )
        }
        for reel in state.clips {
            SocialEntityPersistedCacheCoordinator.saveReel(
                reel,
                viewerID: viewerID,
                source: .profile,
                mergeMode: .replace
            )
        }
        for achievement in state.achievements {
            SocialEntityPersistedCacheCoordinator.saveAchievement(
                achievement,
                viewerID: viewerID,
                source: .profile,
                mergeMode: .replace
            )
        }
    }

    private static func syncTradeEngagement(
        into trades: [TradeSummary],
        engagementStore: EngagementStore
    ) -> [TradeSummary] {
        trades
    }

    private static func patchSectionItem<T: Identifiable & Equatable>(
        viewerID: ProfileID,
        ownerID: ProfileID,
        match: (T) -> Bool,
        upsert: T,
        section: WritableKeyPath<ProfileState, [T]>,
        didLoad: WritableKeyPath<ProfileState, Bool>,
        cap: Int
    ) {
        guard var state = ProfileSessionStore.shared.restore(
            viewerID: viewerID,
            targetProfileID: ownerID
        ) ?? ProfileDiskCache.loadSnapshot(viewerID: viewerID, targetProfileID: ownerID)
            .map(mapBlobToState)
        else { return }
        var items = state[keyPath: section]
        if let index = items.firstIndex(where: match) {
            items[index] = upsert
        } else {
            items.insert(upsert, at: 0)
        }
        state[keyPath: section] = Array(items.prefix(cap))
        state[keyPath: didLoad] = true
        persist(viewerID: viewerID, targetProfileID: ownerID, state: state)
    }

    private static func removeSectionItem<T>(
        viewerID: ProfileID,
        ownerID: ProfileID,
        match: (T) -> Bool,
        section: WritableKeyPath<ProfileState, [T]>
    ) {
        guard var state = ProfileSessionStore.shared.restore(
            viewerID: viewerID,
            targetProfileID: ownerID
        ) ?? ProfileDiskCache.loadSnapshot(viewerID: viewerID, targetProfileID: ownerID)
            .map(mapBlobToState)
        else { return }
        var items = state[keyPath: section]
        guard items.contains(where: match) else { return }
        items.removeAll(where: match)
        state[keyPath: section] = items
        persist(viewerID: viewerID, targetProfileID: ownerID, state: state)
    }
}
