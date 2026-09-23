import Foundation
import Observation

/// Canonical Feed screen owner — one bootstrap, one ``FeedState``, render-only children.
///
/// Matches Profile Bootstrap V2:
/// Screen ViewModel → coordinated bootstrap → shared state → views render / paginate only.
@Observable
@MainActor
final class FeedScreenViewModel {
    typealias Phase = FeedState.Phase

    private(set) var state = FeedState()

    private let feed: any FeedRepository
    private let trades: any TradeRepository
    private let profiles: any ProfileRepository
    private let achievements: any AchievementRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore
    private let vaultStore: VaultStore
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?
    private let rpc: (any RPCClient)?
    private let messages: (any MessageRepository)?
    private weak var currentUserProfile: CurrentUserProfileStore?

    private var bootstrapTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var bootstrapGeneration: UInt64 = 0
    private var pendingNetworkReconcile = false
    private var pendingFeedNetworkReconcile = false
    @ObservationIgnored private nonisolated(unsafe) var blockObserver: NSObjectProtocol?

    init(
        feed: any FeedRepository,
        trades: any TradeRepository,
        profiles: any ProfileRepository,
        achievements: any AchievementRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore,
        vaultStore: VaultStore,
        navigationCoordinator: NavigationCoordinator,
        realtimeHub: RealtimeHub? = nil,
        rpc: (any RPCClient)? = nil,
        messages: (any MessageRepository)? = nil,
        currentUserProfile: CurrentUserProfileStore? = nil
    ) {
        self.feed = feed
        self.trades = trades
        self.profiles = profiles
        self.achievements = achievements
        self.session = session
        self.detailCache = detailCache
        self.engagementStore = engagementStore
        self.vaultStore = vaultStore
        self.navigationCoordinator = navigationCoordinator
        self.realtimeHub = realtimeHub
        self.rpc = rpc
        self.messages = messages
        self.currentUserProfile = currentUserProfile
        blockObserver = NotificationCenter.default.addObserver(
            forName: .userBlockListDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let viewModel = self else { return }
            Task { @MainActor in
                viewModel.applyBlockedAuthorsToLoadedFeed()
            }
        }
    }

    deinit {
        if let blockObserver {
            NotificationCenter.default.removeObserver(blockObserver)
        }
    }

    // MARK: - Published façade (views bind these; owned by ``state``)

    var phase: FeedState.Phase { state.phase }
    var entries: [FeedTimelineEntry] { state.entries }
    var stories: [Story] { state.stories }
    var isRefreshing: Bool { state.isRefreshing }
    var isLoadingMore: Bool { state.isLoadingMore }
    var viewerID: ProfileID? { state.viewerID }
    var visibleEntries: [FeedTimelineEntry] { state.cachedVisibleEntries }
    var visibleEntryIDs: [String] { state.cachedVisibleEntryIDs }
    var showsEmpty: Bool {
        state.showsEmpty
    }

    var isQueryReloadInProgress: Bool {
        state.isQueryReloadInProgress
    }

    var scope: FeedScope {
        get { state.scope }
        set { state.scope = newValue }
    }

    var contentFilter: FeedContentFilter {
        get { state.contentFilter }
        set { state.contentFilter = newValue }
    }

    // MARK: - Lifecycle

    /// Exactly one bootstrap on first presentation.
    func loadIfNeeded() {
        guard bootstrapTask == nil, !state.didBootstrap else { return }
        bootstrapGeneration &+= 1
        let generation = bootstrapGeneration
        bootstrapTask = Task {
            await resolveInitialFeedScopeBeforeBootstrap()
            await performBootstrap(forceNetwork: false, resetting: true, generation: generation, trigger: .initial)
            bootstrapTask = nil
            if pendingNetworkReconcile {
                pendingNetworkReconcile = false
                scheduleDeferredFeedNetworkReconcile(generation: generation)
            }
        }
    }

    func noteTabBecameActive() {
        guard pendingFeedNetworkReconcile else { return }
        pendingFeedNetworkReconcile = false
        let generation = bootstrapGeneration
        scheduleDeferredFeedNetworkReconcile(generation: generation)
    }

    private func scheduleDeferredFeedNetworkReconcile(generation: UInt64) {
        Task(priority: .utility) { @MainActor in
            await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
            guard AuthenticatedLaunchPhasing.activeTab == .feed else {
                self.pendingFeedNetworkReconcile = true
                return
            }
            await self.performBootstrap(
                forceNetwork: true,
                resetting: true,
                generation: generation,
                trigger: .initial
            )
        }
    }

    private func markFeedCriticalVisibleSurfaceReadyIfActive() {
        guard AuthenticatedLaunchPhasing.activeTab == .feed else { return }
        AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .feed)
    }

    /// Standard lifecycle alias for ``loadIfNeeded``.
    func bootstrapIfNeeded() async {
        loadIfNeeded()
        await bootstrapTask?.value
    }

    func refresh() async {
        await refresh(trigger: .pullRefresh)
    }

    /// Phase 10F — bounded first-page head reconcile after Realtime reconnect (merge, no pagination reset).
    func reconcileHeadAfterSocialReconnect(expectedViewerGeneration: UInt64) async {
        guard state.didBootstrap else { return }
        _ = expectedViewerGeneration
        let generation = bootstrapGeneration
        await performBootstrap(
            forceNetwork: true,
            resetting: true,
            generation: generation,
            trigger: .reconnectRepair
        )
        await syncSocialEntityRealtimeBindings()
    }

    func refresh(trigger: FeedLoadTrigger) async {
        cancelInFlightLoads()
        bootstrapGeneration &+= 1
        let generation = bootstrapGeneration
        prepareQueryReload(resetEntriesPhase: false)
        state.isRefreshing = true
        bootstrapTask = Task {
            await performBootstrap(forceNetwork: true, resetting: true, generation: generation, trigger: trigger)
            state.isRefreshing = false
            bootstrapTask = nil
        }
        await bootstrapTask?.value
    }

    /// Inserts or updates a public journal trade on the first page without a blind network replace.
    func applyJournalPublicTrade(_ trade: Trade) {
        guard trade.visibility == .public else {
            state.entries.removeAll { $0.id == trade.id.rawValue }
            rebuildVisibleEntriesCache()
            persistFeedFirstPage()
            return
        }
        detailCache.seed(trade)
        let mediaURL = trade.thumbnail?.id
        let item = FeedItem(
            id: trade.id.rawValue,
            kind: .trade,
            authorProfileID: trade.ownerProfileID,
            createdAt: trade.createdAt,
            tradeID: trade.id,
            postID: nil,
            reelID: nil,
            storyID: nil,
            achievementID: nil,
            caption: trade.publicCaption,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            mediaURL: mediaURL
        )
        FeedBootstrap.seedAuthor(from: item, detailCache: detailCache)
        guard let entry = FeedBootstrap.buildEntryFromItemSync(item, detailCache: detailCache) else { return }
        upsert(entry)
        prefetchEngagement()
    }

    func applyJournalPublicTradeRemoval(tradeID: TradeID) {
        let raw = tradeID.rawValue
        guard state.entries.contains(where: { $0.id == raw }) else { return }
        state.entries.removeAll { $0.id == raw }
        rebuildVisibleEntriesCache()
        persistFeedFirstPage()
    }

    func applyPostRemoval(postID: PostID) {
        guard state.entries.contains(where: { matchesPost($0, postID: postID) }) else { return }
        state.entries.removeAll { matchesPost($0, postID: postID) }
        rebuildVisibleEntriesCache()
        persistFeedFirstPage()
    }

    func applyReelRemoval(reelID: ReelID) {
        guard state.entries.contains(where: { matchesReel($0, reelID: reelID) }) else { return }
        state.entries.removeAll { matchesReel($0, reelID: reelID) }
        rebuildVisibleEntriesCache()
        if let viewerID = state.viewerID {
            SocialEntityPersistedCacheCoordinator.removeReel(id: reelID, viewerID: viewerID)
        }
        persistFeedFirstPage()
    }

    private func matchesPost(_ entry: FeedTimelineEntry, postID: PostID) -> Bool {
        if case .post(_, let post) = entry { return post.id == postID }
        return entry.id == postID.rawValue
    }

    private func matchesReel(_ entry: FeedTimelineEntry, reelID: ReelID) -> Bool {
        if case .clip(_, let reel) = entry { return reel.id == reelID }
        return entry.id == reelID.rawValue
    }

    /// Standard lifecycle — pages using the last visible entry when available.
    func loadMore() async {
        guard let currentID = state.cachedVisibleEntries.last?.id else { return }
        await loadMoreIfNeeded(currentID: currentID)
    }

    func loadMoreIfNeeded(currentID: String) async {
        guard state.hasMore, !state.isLoadingMore, state.phase == .loaded else { return }
        guard bootstrapTask == nil, !state.isRefreshing else { return }
        guard state.cachedVisibleEntries.last?.id == currentID else { return }
        guard paginationTask == nil else { return }

        let generation = bootstrapGeneration
        let queryScope = state.scope
        let queryFilter = state.contentFilter
        let queryCursor = state.nextCursor

        state.isLoadingMore = true
        paginationTask = Task {
            defer {
                if generation == bootstrapGeneration {
                    state.isLoadingMore = false
                }
                paginationTask = nil
            }
            await performBootstrap(
                forceNetwork: true,
                resetting: false,
                generation: generation,
                trigger: .pagination,
                queryScope: queryScope,
                queryFilter: queryFilter,
                queryCursor: queryCursor
            )
        }
        await paginationTask?.value
    }

    func subscribeRealtime() {
        Task { await startRealtimeIfNeeded() }
    }

    func unsubscribeRealtime() {
        stopRealtime()
    }

    func handleRealtimeEvent(_ event: MessageRealtimeSignal) {
        Task { await applyLegacyPostRealtimeBridge(event) }
    }

    private func applyLegacyPostRealtimeBridge(_ signal: MessageRealtimeSignal) async {
        guard let viewerID = state.viewerID else { return }
        bindSocialEntityFeedProcessor(viewerID: viewerID)
        let mutation: SocialEntityRealtimeMutation
        switch signal.kind {
        case .insert: mutation = .insert
        case .update: mutation = .update
        case .delete: mutation = .delete
        }
        guard let raw = signal.messageID else { return }
        let entityEvent = SocialEntityRealtimeEvent(
            table: .posts,
            mutation: mutation,
            entityID: raw,
            authorID: signal.conversationID,
            eventRowID: raw,
            payload: SocialEntityRealtimePayload()
        )
        await SocialEntityRealtimeProcessor.shared.handle(entityEvent, viewerUserID: viewerID.rawValue)
    }

#if DEBUG
    func testing_setLoadedEntries(_ entries: [FeedTimelineEntry], viewerID: ProfileID) {
        publishFeedEntries(entries)
        state.viewerID = viewerID
        state.phase = .loaded
        state.didBootstrap = true
    }

    func testing_setPagination(nextCursor: String?, hasMore: Bool) {
        state.nextCursor = nextCursor
        state.hasMore = hasMore
    }

    func testing_isQueryReloadInProgress() -> Bool {
        bootstrapTask != nil || state.isRefreshing || state.isQueryReloadInProgress
    }

    func testing_applyRealtimeSignal(_ signal: MessageRealtimeSignal) async {
        await applyLegacyPostRealtimeBridge(signal)
    }
#endif

    func setScope(_ next: FeedScope) {
        guard state.scope != next else { return }
        ExperienceHaptics.play(.selection)
        state.scope = next
        Task {
            if let userID = await session.currentUserID {
                FeedScopePreferenceStore.save(next, for: userID)
            }
        }
        if next == .global {
            state.stories = []
        }
        cancelInFlightLoads()
        bootstrapGeneration &+= 1
        let generation = bootstrapGeneration
        hydrateFilterSnapshotFromSessionStore()
        prepareQueryReload(resetEntriesPhase: false)
        state.isQueryReloadInProgress = true
        bootstrapTask = Task {
            await performFilterScopedReload(generation: generation, trigger: .scopeChanged)
            bootstrapTask = nil
        }
    }

    /// User tapped a filter chip — never invoked from SwiftUI bindings on appear.
    func userSelectedContentFilter(_ next: FeedContentFilter) {
        guard state.contentFilter != next else { return }
        ExperienceHaptics.play(.selection)
        state.contentFilter = next
        cancelInFlightLoads()
        bootstrapGeneration &+= 1
        let generation = bootstrapGeneration
        hydrateFilterSnapshotFromSessionStore()
        prepareQueryReload(resetEntriesPhase: false)
        state.isQueryReloadInProgress = true
        bootstrapTask = Task {
            await performFilterScopedReload(generation: generation, trigger: .contentFilterChanged)
            bootstrapTask = nil
        }
    }

    /// Tests / previews — same semantics as an explicit user filter tap.
    func setContentFilter(_ next: FeedContentFilter) {
        userSelectedContentFilter(next)
    }

    func open(_ entry: FeedTimelineEntry) {
        ExperienceHaptics.play(.selection)
        switch entry {
        case .trade(_, let summary):
            detailCache.seedPresentationSeed(DetailPresentationSeed(summary: summary))
            if let postID = entry.feedTradeEngagementPostID {
                detailCache.seedFeedEngagementTarget(.feedPost(postID), forTrade: summary.id)
            }
            #if DEBUG
            TradeSummaryFeedTelemetry.recordDetailBoundary(action: "open", tradeID: summary.id.rawValue)
            #endif
            navigationCoordinator.pushFeed(.trade(summary.id))
        case .post(_, let post):
            detailCache.seed(post)
            navigationCoordinator.pushFeed(.post(post.id))
        case .clip(_, let reel):
            detailCache.seed(reel)
            navigationCoordinator.pushFeed(.reel(reel.id))
        case .achievement(_, let achievement):
            detailCache.seed(achievement)
            detailCache.seedFeedEngagementTarget(entry.interactionTarget, forAchievement: achievement.id)
            navigationCoordinator.pushFeed(.achievement(achievement.id))
        }
    }

    func openAuthor(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushFeed(.profile(profileID))
    }

    func openLinkedTrade(_ tradeID: TradeID) {
        navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
    }

    func openLinkedClip(_ reelID: ReelID) {
        ExperienceHaptics.play(.selection)
        guard let reel = detailCache.reel(id: reelID) else { return }
        detailCache.seed(reel)
        navigationCoordinator.pushFeed(.reel(reelID))
    }

    func openStory(_ story: Story) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(story)
        if let author = detailCache.profile(id: story.authorProfileID)
            ?? FollowListFixtures.profile(id: story.authorProfileID)
        {
            detailCache.seed(author)
        }
        navigationCoordinator.present(fullScreen: .storyViewer(story.id))
    }

    func openCreateStory() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.openCompose(.story)
    }

    /// Inserts a newly published story into the strip without a full feed reload.
    func applyStoryCreated(_ story: Story) {
        guard ActiveStorySemantics.isActive(createdAt: story.createdAt) else { return }
        detailCache.seed(story)
        guard let viewerID = state.viewerID else { return }

        if story.authorProfileID == viewerID {
            ViewerActiveStoryStore.shared.applyStoryCreated(story, viewerID: viewerID)
        }

        guard state.scope == .following else { return }

        if shouldSuppressFeedAuthor(story.authorProfileID), story.authorProfileID != viewerID {
            return
        }

        var catalog = FeedStoriesCatalogStore.shared.catalog
        catalog.removeAll { $0.id == story.id }
        catalog.append(story)
        FeedStoriesCatalogStore.shared.replace(catalog: catalog, viewerID: viewerID)

        if story.authorProfileID == viewerID {
            let others = state.stories.filter { $0.authorProfileID != viewerID }
            state.stories = [story] + others
        } else {
            var merged = state.stories.filter { $0.id != story.id && $0.authorProfileID != story.authorProfileID }
            merged.append(story)
            state.stories = ActiveStorySemantics.stripStories(from: merged, viewerID: viewerID)
        }
        state.lastUpdated = Date()
        persistFeedFirstPage()
    }

    /// Removes a deleted story from the strip without a full feed reload.
    func applyStoryDeleted(_ storyID: StoryID) {
        ViewerActiveStoryStore.shared.applyStoryDeleted(storyID)
        FeedStoriesCatalogStore.shared.removeStory(id: storyID)
        guard state.scope == .following else { return }
        detailCache.removeStory(id: storyID)
        state.stories.removeAll { $0.id == storyID }
        state.lastUpdated = Date()
        persistFeedFirstPage()
    }

    func author(for profileID: ProfileID) -> Profile? {
        detailCache.profile(id: profileID)
            ?? FollowListFixtures.profile(id: profileID)
    }

    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        SocialEntityRealtimeSession.shared.updateFeedBinding(nil)
        SocialEntityRealtimeProcessor.shared.bindFeed(nil)
        Task { [realtimeHub] in
            let channel = RealtimeChannelID(kind: .feed, topic: "home")
            try? await realtimeHub?.subscriptions.unsubscribe(channel)
        }
    }

    // MARK: - Block filtering

    private func syncBlockedAuthorsFromServer(force: Bool) async {
        guard let messages else { return }
        await FeedBlockedAuthorsFilter.shared.syncFromServer(messages: messages, force: force)
        guard let viewerID = state.viewerID else { return }
        let blocked = FeedBlockedAuthorsFilter.shared.blockedPeerIDs
        FeedPersistedCacheCoordinator.persistBlockedPeers(viewerID: viewerID, peers: blocked)
        FeedPersistedCacheCoordinator.pruneBlockedAuthors(viewerID: viewerID, blocked: blocked)
    }

    private func rebuildVisibleEntriesCache() {
        state.rebuildVisibleEntries(blockedPeerIDs: FeedBlockedAuthorsFilter.shared.blockedPeerIDs)
    }

    private func assignFeedEntries(_ entries: [FeedTimelineEntry]) {
        state.entries = entries
        _ = FeedEngagementCacheRestore.seedEngagementStore(from: entries, into: engagementStore)
        rebuildVisibleEntriesCache()
    }

    private func publishFeedEntries(_ entries: [FeedTimelineEntry]) {
        MainThreadWorkProbe.measure("feed.state.publish", surface: "feed") {
            assignFeedEntries(entries)
        }
    }

    private func applyBlockedAuthorsToLoadedFeed(persist: Bool = true) {
        guard let viewerID = state.viewerID else { return }
        let filteredEntries = FeedBlockedAuthorsFilter.shared.filterEntries(state.entries)
        let filteredStories = FeedBlockedAuthorsFilter.shared.filterStories(state.stories, viewerID: viewerID)
        guard filteredEntries != state.entries || filteredStories != state.stories else { return }
        publishFeedEntries(filteredEntries)
        state.stories = filteredStories
        if persist {
            persistFeedFirstPage()
        }
        state.lastUpdated = Date()
    }

    private func persistFeedFirstPage() {
        guard let viewerID = state.viewerID else { return }
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerID,
            scope: state.scope,
            contentFilter: state.contentFilter,
            entries: state.entries,
            stories: state.stories,
            nextCursor: state.nextCursor,
            engagementStore: engagementStore
        )
    }

    private func hydrateDiskFeedCacheIfNeeded(
        scope: FeedScope,
        contentFilter: FeedContentFilter
    ) async -> Bool {
        guard let userID = await session.currentUserID else { return false }
        let viewerID = ProfileID(userID.rawValue)
        state.viewerID = viewerID
        let hydrateStart = Date()
        guard await FeedPersistedCacheCoordinator.hydratePageAsync(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            detailCache: detailCache,
            blockedFilter: FeedBlockedAuthorsFilter.shared
        ) != nil else { return false }
        let resolved = FeedSessionStore.shared.resolvedEntries(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter
        )
        guard !resolved.entries.isEmpty else { return false }
        #if DEBUG
        let exactKey = FeedSessionStore.cacheKey(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            cursor: nil
        )
        let ageMs = FeedSessionStore.shared.restore(key: exactKey).map {
            Int(Date().timeIntervalSince($0.loadedAt) * 1000)
        } ?? 0
        FeedPersistentCacheProbe.recordDiskHit(
            items: resolved.entries.count,
            ageMs: ageMs,
            firstRenderMs: Int(Date().timeIntervalSince(hydrateStart) * 1000)
        )
        MainThreadFreezeProbe.event("feed.diskHydrate", "items=\(resolved.entries.count)")
        #endif
        return true
    }

    private func shouldSuppressFeedAuthor(_ profileID: ProfileID) -> Bool {
        FeedBlockedAuthorsFilter.shared.contains(profileID)
    }

    // MARK: - Bootstrap

    private func resolveInitialFeedScopeBeforeBootstrap() async {
        if ExploreModeSupport.usesLiveCommunityFeed {
            state.scope = ExploreModeSupport.feedScope
            return
        }
        guard let userID = await session.currentUserID else {
            state.scope = .global
            return
        }
        state.scope = await FeedInitialScopeResolver.resolvedInitialScope(
            userID: userID,
            profileStore: currentUserProfile
        )
    }

    private func cancelInFlightLoads() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        state.isLoadingMore = false
    }

    /// Synchronously drop pagination state so stale tail rows cannot page during a query reload.
    private func prepareQueryReload(resetEntriesPhase: Bool) {
        state.nextCursor = nil
        state.hasMore = false
        if resetEntriesPhase, state.entries.isEmpty {
            state.phase = .loading
        }
    }

    /// Synchronously apply session cache / sibling-filter rows before a scoped reload.
    private func hydrateFilterSnapshotFromSessionStore() {
        guard let viewerID = state.viewerID else { return }
        let resolved = FeedSessionStore.shared.resolvedEntries(
            viewerID: viewerID,
            scope: state.scope,
            contentFilter: state.contentFilter
        )
        let key = FeedState.firstPageCacheKey(
            viewerID: viewerID,
            scope: state.scope,
            contentFilter: state.contentFilter
        )
        let knownEmpty = key.map { state.knownEmptyFilterKeys.contains($0) } ?? false
        FeedFilterCacheProbe.logHydrate(
            filter: state.contentFilter,
            scope: state.scope,
            source: resolved.source,
            cachedCount: resolved.entries.count,
            knownEmpty: knownEmpty
        )
        guard !resolved.entries.isEmpty else { return }
        MainThreadWorkProbe.measure("feed.rows.transform", surface: "feed") {
            publishFeedEntries(FeedBlockedAuthorsFilter.shared.filterEntries(resolved.entries))
        }
        if state.scope == .following,
           let exact = FeedSessionStore.shared.restore(
            key: FeedSessionStore.cacheKey(
                viewerID: viewerID,
                scope: state.scope,
                contentFilter: state.contentFilter,
                cursor: nil
            )
           ) {
            state.stories = FeedBlockedAuthorsFilter.shared.filterStories(
                exact.stories,
                viewerID: viewerID
            )
            state.nextCursor = exact.nextCursor
            state.hasMore = exact.nextCursor != nil
        }
        if state.phase != .loaded {
            state.phase = .loaded
        }
        if let key, knownEmpty {
            state.knownEmptyFilterKeys.remove(key)
        }
    }

    /// Cache-first reload, then authoritative network refresh (stale-while-revalidate).
    private func performFilterScopedReload(generation: UInt64, trigger: FeedLoadTrigger) async {
        await performBootstrap(
            forceNetwork: false,
            resetting: true,
            generation: generation,
            trigger: trigger
        )
        state.isQueryReloadInProgress = false
        guard generation == bootstrapGeneration, !Task.isCancelled else { return }
        Task(priority: .utility) { @MainActor in
            await self.performBootstrap(
                forceNetwork: true,
                resetting: true,
                generation: generation,
                trigger: trigger
            )
        }
    }

    private func noteFilterLoadResult(
        entries: [FeedTimelineEntry],
        scope: FeedScope,
        filter: FeedContentFilter,
        viewerID: ProfileID?
    ) {
        guard let viewerID,
              let key = FeedState.firstPageCacheKey(
                viewerID: viewerID,
                scope: scope,
                contentFilter: filter
              )
        else { return }
        let visible = entries.filter { $0.matches(filter: filter) }
        if visible.isEmpty {
            state.knownEmptyFilterKeys.insert(key)
        } else {
            state.knownEmptyFilterKeys.remove(key)
        }
        FeedFilterCacheProbe.logNetworkRefresh(
            filter: filter,
            scope: scope,
            resultCount: visible.count,
            knownEmpty: visible.isEmpty
        )
    }

    private func shouldApplyBootstrapResult(
        generation: UInt64,
        resetting: Bool,
        queryScope: FeedScope,
        queryFilter: FeedContentFilter,
        queryCursor: String?
    ) -> Bool {
        guard generation == bootstrapGeneration, !Task.isCancelled else { return false }
        guard state.scope == queryScope, state.contentFilter == queryFilter else { return false }
        if !resetting {
            guard state.nextCursor == queryCursor else { return false }
        }
        return true
    }

    private func performBootstrap(
        forceNetwork: Bool,
        resetting: Bool,
        generation: UInt64? = nil,
        trigger: FeedLoadTrigger,
        queryScope: FeedScope? = nil,
        queryFilter: FeedContentFilter? = nil,
        queryCursor: String? = nil
    ) async {
        FeedLoadProbe.record(trigger)
        let activeGeneration = generation ?? bootstrapGeneration
        let resolvedScope = queryScope ?? state.scope
        let resolvedFilter = queryFilter ?? state.contentFilter
        let resolvedCursor = resetting ? nil : (queryCursor ?? state.nextCursor)
        let existingForReconcile = resetting && forceNetwork && resolvedCursor == nil
            ? state.entries
            : []

        if resetting, resolvedCursor == nil {
            if !forceNetwork {
                _ = await hydrateDiskFeedCacheIfNeeded(scope: resolvedScope, contentFilter: resolvedFilter)
            }
            hydrateFilterSnapshotFromSessionStore()
        } else if resetting, !forceNetwork {
            hydrateFilterSnapshotFromSessionStore()
        }

        let hadCachedFirstRender = resetting && resolvedCursor == nil && !state.entries.isEmpty
        #if DEBUG
        if resetting, resolvedCursor == nil {
            let resolved = state.viewerID.map {
                FeedSessionStore.shared.resolvedEntries(
                    viewerID: $0,
                    scope: resolvedScope,
                    contentFilter: resolvedFilter
                )
            }
            CacheDecisionProbe.log(
                surface: "feed",
                cacheExists: resolved?.entries.isEmpty == false,
                cacheUsable: hadCachedFirstRender,
                action: hadCachedFirstRender ? "renderCache" : "networkRequired",
                reason: forceNetwork
                    ? "backgroundReconcile"
                    : (resolved?.source.rawValue ?? "none")
            )
            let cacheSource = hadCachedFirstRender
                ? "disk"
                : (resolved?.source.rawValue ?? "none")
            FeedLoadTrace.log(
                trigger: trigger,
                generation: activeGeneration,
                scope: resolvedScope,
                filter: resolvedFilter,
                caller: "FeedScreenViewModel.performBootstrap",
                cacheSource: cacheSource,
                networkRequired: !hadCachedFirstRender || forceNetwork
            )
        }
        #endif

        let guestPublicFeed = ExploreModeSupport.skipsAuthenticatedViewerServices
        let blockPeerSync: Task<Void, Never>?
        if resetting {
            if guestPublicFeed {
                blockPeerSync = nil
            } else if forceNetwork || !FeedBlockedAuthorsFilter.shared.hasSyncedFromServer {
                blockPeerSync = Task {
                    await syncBlockedAuthorsFromServer(force: forceNetwork)
                }
            } else {
                blockPeerSync = nil
            }
            if state.cachedVisibleEntries.isEmpty, state.entries.isEmpty, !hadCachedFirstRender {
                state.phase = .loading
            }
            if !(hadCachedFirstRender && forceNetwork) {
                state.nextCursor = nil
                state.hasMore = false
            }
        } else {
            blockPeerSync = nil
        }

        if BackendV2FeatureFlags.isEnabled(.feed), let rpc {
            let sessionUserID = await session.currentUserID
            if guestPublicFeed || sessionUserID != nil {
                let viewerID: ProfileID
                if guestPublicFeed {
                    viewerID = ExploreModeSupport.guestFeedViewerID
                } else if let userID = sessionUserID {
                    viewerID = ProfileID(userID.rawValue)
                } else {
                    viewerID = ExploreModeSupport.guestFeedViewerID
                }
                let feedScope = guestPublicFeed ? FeedScope.global : resolvedScope
                if hadCachedFirstRender && !forceNetwork && resolvedCursor == nil {
                    #if DEBUG
                    FeedLoadTrace.log(
                        trigger: trigger,
                        generation: activeGeneration,
                        scope: resolvedScope,
                        filter: resolvedFilter,
                        caller: "FeedScreenViewModel.performBootstrap.cacheOnlyReturn",
                        cacheSource: "disk",
                        networkRequired: false
                    )
                    #endif
                    state.viewerID = viewerID
                    state.phase = .loaded
                    state.didBootstrap = true
                    pendingNetworkReconcile = true
                    markFeedCriticalVisibleSurfaceReadyIfActive()
                    prefetchEngagement(source: .memory)
                    if blockPeerSync != nil {
                        Task(priority: .utility) { @MainActor in
                            await blockPeerSync?.value
                            self.applyBlockedAuthorsToLoadedFeed(persist: false)
                        }
                    }
                    Task { await startRealtimeIfNeeded() }
                    return
                }
                do {
                    let loaded = try await FeedBootstrapLoader.loadTimeline(
                        viewerID: viewerID,
                        scope: feedScope,
                        contentFilter: resolvedFilter,
                        cursor: resolvedCursor,
                        limit: 20,
                        rpc: rpc,
                        feed: feed,
                        trades: trades,
                        profiles: profiles,
                        achievements: achievements,
                        detailCache: detailCache,
                        forceNetwork: forceNetwork,
                        allowNetwork: forceNetwork || !hadCachedFirstRender,
                        guestPublicMode: guestPublicFeed,
                        traceTrigger: forceNetwork ? "feed.reconcile" : "feed.initial"
                    )
                    guard shouldApplyBootstrapResult(
                        generation: activeGeneration,
                        resetting: resetting,
                        queryScope: resolvedScope,
                        queryFilter: resolvedFilter,
                        queryCursor: resolvedCursor
                    ) else { return }
                    state.viewerID = viewerID
                    let filteredEntries = FeedBlockedAuthorsFilter.shared.filterEntries(loaded.entries)
                    let filteredStories = FeedBlockedAuthorsFilter.shared.filterStories(
                        loaded.stories,
                        viewerID: viewerID
                    )
                    if resetting {
                        if forceNetwork && !existingForReconcile.isEmpty && resolvedCursor == nil {
                            let reconcileStart = Date()
                            let result = FeedPersistentReconcile.reconcileFirstPage(
                                existing: existingForReconcile,
                                incoming: filteredEntries,
                                preserveEntryIDs: ownerPublicFeedEntryPreserveIDs(viewerID: viewerID)
                            )
                            MainThreadWorkProbe.measure("feed.reconcileApply", surface: "feed") {
                                assignFeedEntries(
                                    FeedBlockedAuthorsFilter.shared.filterEntries(result.entries)
                                )
                            }
                            #if DEBUG
                            FeedPersistentCacheProbe.recordReconcile(
                                inserted: result.inserted,
                                updated: result.updated,
                                removed: result.removed,
                                durationMs: Int(Date().timeIntervalSince(reconcileStart) * 1000)
                            )
                            #endif
                        } else {
                            MainThreadWorkProbe.measure("feed.bootstrapApply", surface: "feed") {
                                assignFeedEntries(filteredEntries)
                            }
                        }
                        state.stories = filteredStories
                        syncViewerStoryStoreIfNeeded()
                        if resolvedCursor == nil {
                            noteFilterLoadResult(
                                entries: state.entries,
                                scope: resolvedScope,
                                filter: resolvedFilter,
                                viewerID: viewerID
                            )
                            persistFeedFirstPage()
                        }
                    } else {
                        let existing = Set(state.entries.map(\.id))
                        let appended = filteredEntries.filter { !existing.contains($0.id) }
                        assignFeedEntries(FeedSupport.sortDescending(state.entries + appended))
                    }
                    state.nextCursor = loaded.nextCursor
                    state.hasMore = loaded.nextCursor != nil
                    for (target, snapshot) in loaded.engagement {
                        engagementStore.seed(snapshot, for: target)
                    }
                    if loaded.engagement.isEmpty {
                        prefetchEngagement()
                    }
                    state.phase = .loaded
                    state.didBootstrap = true
                    state.lastUpdated = Date()
                    if resetting, resolvedCursor == nil {
                        markFeedCriticalVisibleSurfaceReadyIfActive()
                    }
                    if hadCachedFirstRender && !forceNetwork && resolvedCursor == nil {
                        pendingNetworkReconcile = true
                    }
                    scheduleBackgroundEntryHydration(
                        items: loaded.pendingHydrationItems,
                        feedItemOrder: loaded.feedItemOrder,
                        generation: activeGeneration,
                        resetting: resetting,
                        queryScope: resolvedScope,
                        queryFilter: resolvedFilter,
                        queryCursor: resolvedCursor,
                        viewerID: viewerID
                    )
                    await blockPeerSync?.value
                    applyBlockedAuthorsToLoadedFeed()
                    await startRealtimeIfNeeded()
                    return
                } catch FeedBootstrapLoader.LoaderError.cacheMissSkipped {
                    guard shouldApplyBootstrapResult(
                        generation: activeGeneration,
                        resetting: resetting,
                        queryScope: resolvedScope,
                        queryFilter: resolvedFilter,
                        queryCursor: resolvedCursor
                    ) else { return }
                    if hadCachedFirstRender && !forceNetwork {
                        state.phase = .loaded
                        state.didBootstrap = true
                        pendingNetworkReconcile = true
                        await blockPeerSync?.value
                        applyBlockedAuthorsToLoadedFeed()
                        await startRealtimeIfNeeded()
                        return
                    }
                } catch is FeedBootstrapLoader.LoaderError {
                    // Controlled fallback to legacy REST merge.
                } catch {
                    guard shouldApplyBootstrapResult(
                        generation: activeGeneration,
                        resetting: resetting,
                        queryScope: resolvedScope,
                        queryFilter: resolvedFilter,
                        queryCursor: resolvedCursor
                    ) else { return }
                    await blockPeerSync?.value
                    applyBlockedAuthorsToLoadedFeed()
                    if state.entries.isEmpty {
                        state.phase = .failed(FeedSupport.message(for: error))
                    }
                    return
                }
            }
        }

        let context = FeedBootstrap.Context(
            feed: feed,
            trades: trades,
            profiles: profiles,
            achievements: achievements,
            session: session,
            detailCache: detailCache,
            scope: resolvedScope,
            contentFilter: resolvedFilter,
            cursor: resolvedCursor
        )

        do {
            let page: FeedBootstrap.PageResult
            if resetting {
                page = try await FeedBootstrap.loadInitial(context)
            } else {
                page = try await FeedBootstrap.loadMore(context)
            }
            guard shouldApplyBootstrapResult(
                generation: activeGeneration,
                resetting: resetting,
                queryScope: resolvedScope,
                queryFilter: resolvedFilter,
                queryCursor: resolvedCursor
            ) else { return }

            state.viewerID = page.viewerID
            let filteredEntries = FeedBlockedAuthorsFilter.shared.filterEntries(page.entries)
            let filteredStories: [Story]
            if let viewerID = page.viewerID {
                filteredStories = FeedBlockedAuthorsFilter.shared.filterStories(page.stories, viewerID: viewerID)
            } else {
                filteredStories = page.stories
            }
            if resetting {
                assignFeedEntries(filteredEntries)
                state.stories = filteredStories
                syncViewerStoryStoreIfNeeded()
                if resolvedCursor == nil {
                    noteFilterLoadResult(
                        entries: filteredEntries,
                        scope: resolvedScope,
                        filter: resolvedFilter,
                        viewerID: page.viewerID
                    )
                    if let viewerID = page.viewerID {
                        FeedPersistedCacheCoordinator.persistFirstPage(
                            viewerID: viewerID,
                            scope: resolvedScope,
                            contentFilter: resolvedFilter,
                            entries: filteredEntries,
                            stories: filteredStories,
                            nextCursor: page.nextCursor,
                            engagementStore: engagementStore
                        )
                    }
                }
            } else {
                let existing = Set(state.entries.map(\.id))
                let appended = filteredEntries.filter { !existing.contains($0.id) }
                assignFeedEntries(FeedSupport.sortDescending(state.entries + appended))
            }
            state.nextCursor = page.nextCursor
            state.hasMore = page.nextCursor != nil
            if page.usedDevelopmentFixtures {
                state.hasMore = false
            }
            prefetchEngagement()
            state.phase = .loaded
            state.didBootstrap = true
            state.lastUpdated = Date()
            if let viewerID = page.viewerID {
                await FollowMutationCoordinator.shared.hydrateViewerFollowingRelationshipsIfNeeded(viewer: viewerID)
            }
            await blockPeerSync?.value
            applyBlockedAuthorsToLoadedFeed()
            await startRealtimeIfNeeded()
        } catch {
            guard shouldApplyBootstrapResult(
                generation: activeGeneration,
                resetting: resetting,
                queryScope: resolvedScope,
                queryFilter: resolvedFilter,
                queryCursor: resolvedCursor
            ) else { return }
            await blockPeerSync?.value
            applyBlockedAuthorsToLoadedFeed()
            if state.entries.isEmpty {
                state.phase = .failed(FeedSupport.message(for: error))
            } else {
                state.phase = .loaded
            }
        }
    }

    private func prefetchEngagement(source: FeedEngagementCacheProbe.FeedSource = .network) {
        let visible = state.cachedVisibleEntries
        let summary = FeedEngagementCacheRestore.seedEngagementStore(from: visible, into: engagementStore)
        let targets = visible.map(\.interactionTarget)
        let missing = targets.filter { !engagementStore.hasLoaded($0) }
        #if DEBUG
        FeedEngagementCacheProbe.logRestore(
            source: source,
            summary: summary,
            totalVisibleTargets: targets.count,
            missingAfterRestore: missing.count,
            networkFallbackScheduled: !missing.isEmpty
        )
        #endif
        if !missing.isEmpty {
            engagementStore.prefetch(missing)
        }
        EngagementRealtimeSession.shared.updateRetention(
            ownerKey: "feed-visible",
            targets: Set(targets)
        )
        Task { await syncSocialEntityRealtimeBindings() }
        let vaultRefs = visible.compactMap { VaultContentRef.from($0.interactionTarget) }
        vaultStore.prefetch(vaultRefs)
    }

    /// Network hydration for rows that could not be built from bootstrap embeds alone.
    private func scheduleBackgroundEntryHydration(
        items: [FeedItem],
        feedItemOrder: [String],
        generation: UInt64,
        resetting: Bool,
        queryScope: FeedScope,
        queryFilter: FeedContentFilter,
        queryCursor: String?,
        viewerID: ProfileID
    ) {
        guard !items.isEmpty else { return }
        Task {
            #if DEBUG
            FeedRpcLoadProbe.recordNetworkHydrate()
            #endif
            var hydrated = await FeedBootstrap.hydrate(
                items,
                feed: feed,
                trades: trades,
                profiles: profiles,
                achievements: achievements,
                detailCache: detailCache
            )
            let hydratedIDs = Set(hydrated.map(\.id))
            let stillMissing = items.filter { !hydratedIDs.contains($0.id) }
            if !stillMissing.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled {
                    let retryHydrated = await FeedBootstrap.hydrate(
                        stillMissing,
                        feed: feed,
                        trades: trades,
                        profiles: profiles,
                        achievements: achievements,
                        detailCache: detailCache
                    )
                    hydrated.append(contentsOf: retryHydrated)
                }
            }
            guard shouldApplyBootstrapResult(
                generation: generation,
                resetting: resetting,
                queryScope: queryScope,
                queryFilter: queryFilter,
                queryCursor: queryCursor
            ), !hydrated.isEmpty else { return }

            let merged = FeedBootstrap.mergeHydratedEntries(
                existing: state.entries,
                hydrated: hydrated,
                feedItemOrder: feedItemOrder
            )
            assignFeedEntries(FeedBlockedAuthorsFilter.shared.filterEntries(merged))
            state.lastUpdated = Date()
            prefetchEngagement()

            if queryCursor == nil {
                noteFilterLoadResult(
                    entries: state.entries,
                    scope: queryScope,
                    filter: queryFilter,
                    viewerID: viewerID
                )
                FeedPersistedCacheCoordinator.persistFirstPage(
                    viewerID: viewerID,
                    scope: queryScope,
                    contentFilter: queryFilter,
                    entries: state.entries,
                    stories: state.stories,
                    nextCursor: state.nextCursor,
                    engagementStore: engagementStore
                )
            }
        }
    }

    private func syncViewerStoryStoreIfNeeded() {
        guard state.scope == .following, let viewerID = state.viewerID else { return }
        ViewerActiveStoryStore.shared.sync(viewerID: viewerID, stories: state.stories)
    }

    // MARK: - Realtime (screen-owned only)

    private func startRealtimeIfNeeded() async {
        guard realtimeHub != nil else { return }
        guard !ExploreModeSupport.skipsAuthenticatedViewerServices else { return }
        guard let viewerID = state.viewerID,
              !FeedSupport.isLocalDevelopmentProfile(viewerID) else { return }
        guard realtimeTask == nil else { return }

        let channel = RealtimeChannelID(kind: .feed, topic: "home")
        await MainThreadWorkProbe.measureAsync("feed.realtime.setup", surface: "feed") {
            try? await realtimeHub?.subscriptions.subscribe(channel)
        }
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            await self.syncSocialEntityRealtimeBindings()
            self.realtimeTask = nil
        }
    }

    func syncSocialEntityRealtimeBindings() async {
        guard let viewerID = state.viewerID else { return }
        bindSocialEntityFeedProcessor(viewerID: viewerID)
        var followingAuthors: Set<String>?
        if state.scope == .following {
            if await SessionFollowingStore.shared.isComplete(viewerID: viewerID.rawValue),
               let cached = await SessionFollowingStore.shared.cached(viewerID: viewerID.rawValue)
            {
                followingAuthors = cached
            }
        }
        SocialEntityRealtimeSession.shared.updateFeedBinding(
            SocialEntityRealtimeSession.FeedBinding(
                viewerID: viewerID,
                scope: state.scope,
                followingAuthorIDs: followingAuthors,
                trackedEntityIDsByTable: trackedEntityIDsByTable()
            )
        )
    }

    private func bindSocialEntityFeedProcessor(viewerID: ProfileID) {
        SocialEntityRealtimeProcessor.shared.bindFeed(
            SocialEntityRealtimeProcessor.FeedContext(
                viewerID: viewerID,
                scope: state.scope,
                contentFilter: state.contentFilter,
                trackedEntityIDsByTable: trackedEntityIDsByTable(),
                onInsert: { [weak self] entry in
                    self?.upsert(entry)
                },
                onUpdate: { [weak self] entry in
                    self?.upsert(entry)
                },
                onDelete: { [weak self] entryID in
                    self?.removeFeedEntry(id: entryID)
                },
                persistFirstPage: { [weak self] in
                    self?.persistFeedFirstPage()
                }
            )
        )
    }

    private func trackedEntityIDsByTable() -> [SocialEntityRealtimeTable: Set<String>] {
        var map: [SocialEntityRealtimeTable: Set<String>] = [:]
        for entry in state.entries {
            switch entry {
            case .trade:
                map[.trades, default: []].insert(entry.id)
            case .post:
                map[.profilePosts, default: []].insert(entry.id)
                map[.posts, default: []].insert(entry.id)
            case .clip:
                map[.reels, default: []].insert(entry.id)
            case .achievement:
                map[.achievementPosts, default: []].insert(entry.id)
            }
        }
        return map
    }

    private func removeFeedEntry(id: String) {
        state.entries.removeAll { $0.id == id || $0.item.postID?.rawValue == id }
        rebuildVisibleEntriesCache()
    }

    private func upsert(_ entry: FeedTimelineEntry) {
        var working = state.entries
        if let index = working.firstIndex(where: { $0.id == entry.id }) {
            working[index] = entry
        } else {
            working.append(entry)
        }
        assignFeedEntries(FeedSupport.sortDescending(working))
        persistFeedFirstPage()
    }

    private func ownerPublicFeedEntryPreserveIDs(viewerID: ProfileID) -> Set<String> {
        Set(
            (SessionOwnerTradesStore.shared.cached(for: viewerID) ?? [])
                .filter { $0.visibility == .public }
                .map(\.id.rawValue)
        )
    }
}

extension FeedScreenViewModel: ScreenLifecycle, ScreenRealtimeHandling {}

/// Compatibility alias — tests and call sites may still reference ``FeedViewModel``.
typealias FeedViewModel = FeedScreenViewModel
