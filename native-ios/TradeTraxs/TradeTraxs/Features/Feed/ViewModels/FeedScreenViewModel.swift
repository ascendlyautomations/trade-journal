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

    private var bootstrapTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var bootstrapGeneration: UInt64 = 0
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
        messages: (any MessageRepository)? = nil
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
    var visibleEntries: [FeedTimelineEntry] {
        let filtered = state.entries.filter { $0.matches(filter: state.contentFilter) }
        return FeedBlockedAuthorsFilter.shared.filterEntries(filtered)
    }
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
            await performBootstrap(forceNetwork: false, resetting: true, generation: generation, trigger: .initial)
            bootstrapTask = nil
        }
    }

    /// Standard lifecycle alias for ``loadIfNeeded``.
    func bootstrapIfNeeded() async {
        loadIfNeeded()
        await bootstrapTask?.value
    }

    func refresh() async {
        await refresh(trigger: .pullRefresh)
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

    /// Standard lifecycle — pages using the last visible entry when available.
    func loadMore() async {
        guard let currentID = state.visibleEntries.last?.id else { return }
        await loadMoreIfNeeded(currentID: currentID)
    }

    func loadMoreIfNeeded(currentID: String) async {
        guard state.hasMore, !state.isLoadingMore, state.phase == .loaded else { return }
        guard bootstrapTask == nil, !state.isRefreshing else { return }
        guard state.visibleEntries.last?.id == currentID else { return }
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
        Task { await applyRealtimeSignal(event) }
    }

#if DEBUG
    func testing_setLoadedEntries(_ entries: [FeedTimelineEntry], viewerID: ProfileID) {
        state.entries = entries
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
        await applyRealtimeSignal(signal)
    }
#endif

    func setScope(_ next: FeedScope) {
        guard state.scope != next else { return }
        ExperienceHaptics.play(.selection)
        state.scope = next
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
        case .trade(_, let trade):
            detailCache.seed(trade)
            if let postID = entry.feedTradeEngagementPostID {
                detailCache.seedFeedEngagementTarget(.feedPost(postID), forTrade: trade.id)
            }
            navigationCoordinator.open(.feed(.trade(trade.id)))
        case .post(_, let post):
            detailCache.seed(post)
            navigationCoordinator.open(.feed(.post(post.id)))
        case .clip(_, let reel):
            detailCache.seed(reel)
            navigationCoordinator.open(.feed(.reel(reel.id)))
        case .achievement(_, let achievement):
            detailCache.seed(achievement)
            detailCache.seedFeedEngagementTarget(entry.interactionTarget, forAchievement: achievement.id)
            navigationCoordinator.open(.feed(.achievement(achievement.id)))
        }
    }

    func openAuthor(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.feed(.profile(profileID)))
    }

    func openLinkedTrade(_ tradeID: TradeID) {
        navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
    }

    func openLinkedClip(_ reelID: ReelID) {
        ExperienceHaptics.play(.selection)
        guard let reel = detailCache.reel(id: reelID) else { return }
        detailCache.seed(reel)
        navigationCoordinator.open(.feed(.reel(reelID)))
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
    }

    /// Removes a deleted story from the strip without a full feed reload.
    func applyStoryDeleted(_ storyID: StoryID) {
        ViewerActiveStoryStore.shared.applyStoryDeleted(storyID)
        FeedStoriesCatalogStore.shared.removeStory(id: storyID)
        guard state.scope == .following else { return }
        detailCache.removeStory(id: storyID)
        state.stories.removeAll { $0.id == storyID }
        state.lastUpdated = Date()
    }

    func author(for profileID: ProfileID) -> Profile? {
        detailCache.profile(id: profileID)
            ?? FollowListFixtures.profile(id: profileID)
    }

    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        Task { [realtimeHub] in
            let channel = RealtimeChannelID(kind: .feed, topic: "home")
            try? await realtimeHub?.subscriptions.unsubscribe(channel)
            await realtimeHub?.stopWatchingFeedPosts()
        }
    }

    // MARK: - Block filtering

    private func syncBlockedAuthorsFromServer(force: Bool) async {
        guard let messages else { return }
        await FeedBlockedAuthorsFilter.shared.syncFromServer(messages: messages, force: force)
    }

    private func applyBlockedAuthorsToLoadedFeed() {
        guard let viewerID = state.viewerID else { return }
        state.entries = FeedBlockedAuthorsFilter.shared.filterEntries(state.entries)
        state.stories = FeedBlockedAuthorsFilter.shared.filterStories(state.stories, viewerID: viewerID)
        state.lastUpdated = Date()
    }

    private func shouldSuppressFeedAuthor(_ profileID: ProfileID) -> Bool {
        FeedBlockedAuthorsFilter.shared.contains(profileID)
    }

    // MARK: - Bootstrap

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
        state.entries = FeedBlockedAuthorsFilter.shared.filterEntries(resolved.entries)
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
        await performBootstrap(
            forceNetwork: true,
            resetting: true,
            generation: generation,
            trigger: trigger
        )
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

        if resetting {
            await syncBlockedAuthorsFromServer(force: forceNetwork)
            if state.visibleEntries.isEmpty, state.entries.isEmpty {
                state.phase = .loading
            }
            state.nextCursor = nil
            state.hasMore = false
        }

        if BackendV2FeatureFlags.isEnabled(.feed), let rpc {
            if let userID = await session.currentUserID {
                let viewerID = ProfileID(userID.rawValue)
                do {
                    let loaded = try await FeedBootstrapLoader.loadTimeline(
                        viewerID: viewerID,
                        scope: resolvedScope,
                        contentFilter: resolvedFilter,
                        cursor: resolvedCursor,
                        limit: 20,
                        rpc: rpc,
                        feed: feed,
                        trades: trades,
                        profiles: profiles,
                        achievements: achievements,
                        detailCache: detailCache,
                        forceNetwork: forceNetwork
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
                        state.entries = filteredEntries
                        state.stories = filteredStories
                        syncViewerStoryStoreIfNeeded()
                        if resolvedCursor == nil {
                            noteFilterLoadResult(
                                entries: filteredEntries,
                                scope: resolvedScope,
                                filter: resolvedFilter,
                                viewerID: viewerID
                            )
                        }
                    } else {
                        let existing = Set(state.entries.map(\.id))
                        let appended = filteredEntries.filter { !existing.contains($0.id) }
                        state.entries = FeedSupport.sortDescending(state.entries + appended)
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
                    await startRealtimeIfNeeded()
                    return
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
                state.entries = filteredEntries
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
                        FeedSessionStore.shared.save(
                            FeedSessionStore.Snapshot(
                                cacheKey: FeedSessionStore.cacheKey(
                                    viewerID: viewerID,
                                    scope: resolvedScope,
                                    contentFilter: resolvedFilter,
                                    cursor: nil
                                ),
                                entries: filteredEntries,
                                stories: filteredStories,
                                nextCursor: page.nextCursor,
                                loadedAt: Date()
                            )
                        )
                    }
                }
            } else {
                let existing = Set(state.entries.map(\.id))
                let appended = filteredEntries.filter { !existing.contains($0.id) }
                state.entries = FeedSupport.sortDescending(state.entries + appended)
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
            await startRealtimeIfNeeded()
        } catch {
            guard shouldApplyBootstrapResult(
                generation: activeGeneration,
                resetting: resetting,
                queryScope: resolvedScope,
                queryFilter: resolvedFilter,
                queryCursor: resolvedCursor
            ) else { return }
            if state.entries.isEmpty {
                state.phase = .failed(FeedSupport.message(for: error))
            } else {
                state.phase = .loaded
            }
        }
    }

    private func prefetchEngagement() {
        let targets = state.visibleEntries.map(\.interactionTarget)
        engagementStore.prefetch(targets)
        let vaultRefs = state.visibleEntries.compactMap { VaultContentRef.from($0.interactionTarget) }
        vaultStore.prefetch(vaultRefs)
    }

    private func syncViewerStoryStoreIfNeeded() {
        guard state.scope == .following, let viewerID = state.viewerID else { return }
        ViewerActiveStoryStore.shared.sync(viewerID: viewerID, stories: state.stories)
    }

    // MARK: - Realtime (screen-owned only)

    private func startRealtimeIfNeeded() async {
        guard let realtimeHub else { return }
        guard let viewerID = state.viewerID,
              !FeedSupport.isLocalDevelopmentProfile(viewerID) else { return }
        guard realtimeTask == nil else { return }

        let channel = RealtimeChannelID(kind: .feed, topic: "home")
        try? await realtimeHub.subscriptions.subscribe(channel)
        let token = await session.accessToken

        realtimeTask = Task { [weak self] in
            guard let self else { return }
            for await signal in realtimeHub.watchFeedPosts(accessToken: token) {
                guard !Task.isCancelled else { break }
                await applyRealtimeSignal(signal)
            }
            realtimeTask = nil
        }
    }

    private func applyRealtimeSignal(_ signal: MessageRealtimeSignal) async {
        switch signal.kind {
        case .delete:
            guard let raw = signal.messageID else { return }
            state.entries.removeAll { $0.item.postID?.rawValue == raw || $0.id == raw }
        case .insert, .update:
            guard let raw = signal.messageID else { return }
            let postID = PostID(raw)
            guard let post = try? await feed.post(id: postID) else { return }
            guard !shouldSuppressFeedAuthor(post.authorProfileID) else { return }
            detailCache.seed(post)
            let kind: FeedItemKind = post.linkedTradeID == nil ? .post : .trade
            let item = FeedItem(
                id: post.id.rawValue,
                kind: kind,
                authorProfileID: post.authorProfileID,
                createdAt: post.createdAt,
                tradeID: post.linkedTradeID,
                postID: post.id,
                reelID: nil,
                storyID: nil,
                achievementID: nil,
                caption: post.body,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false
            )
            FeedBootstrap.seedAuthor(from: item, detailCache: detailCache)
            if let hydrated = await FeedBootstrap.hydrateOne(
                item,
                feed: feed,
                trades: trades,
                profiles: profiles,
                achievements: achievements,
                detailCache: detailCache
            ) {
                upsert(hydrated)
                prefetchEngagement()
            }
        }
    }

    private func upsert(_ entry: FeedTimelineEntry) {
        if let index = state.entries.firstIndex(where: { $0.id == entry.id }) {
            state.entries[index] = entry
        } else {
            state.entries.append(entry)
        }
        state.entries = FeedSupport.sortDescending(state.entries)
    }
}

extension FeedScreenViewModel: ScreenLifecycle, ScreenRealtimeHandling {}

/// Compatibility alias — tests and call sites may still reference ``FeedViewModel``.
typealias FeedViewModel = FeedScreenViewModel
