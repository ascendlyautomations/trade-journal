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
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?

    private var bootstrapTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?

    init(
        feed: any FeedRepository,
        trades: any TradeRepository,
        profiles: any ProfileRepository,
        achievements: any AchievementRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore,
        navigationCoordinator: NavigationCoordinator,
        realtimeHub: RealtimeHub? = nil
    ) {
        self.feed = feed
        self.trades = trades
        self.profiles = profiles
        self.achievements = achievements
        self.session = session
        self.detailCache = detailCache
        self.engagementStore = engagementStore
        self.navigationCoordinator = navigationCoordinator
        self.realtimeHub = realtimeHub
    }

    // MARK: - Published façade (views bind these; owned by ``state``)

    var phase: FeedState.Phase { state.phase }
    var entries: [FeedTimelineEntry] { state.entries }
    var stories: [Story] { state.stories }
    var isRefreshing: Bool { state.isRefreshing }
    var isLoadingMore: Bool { state.isLoadingMore }
    var viewerID: ProfileID? { state.viewerID }
    var visibleEntries: [FeedTimelineEntry] { state.visibleEntries }
    var showsEmpty: Bool { state.showsEmpty }

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
        bootstrapTask = Task { await performBootstrap(forceNetwork: false, resetting: true) }
    }

    /// Standard lifecycle alias for ``loadIfNeeded``.
    func bootstrapIfNeeded() async {
        loadIfNeeded()
        await bootstrapTask?.value
    }

    func refresh() async {
        bootstrapTask?.cancel()
        state.isRefreshing = true
        await performBootstrap(forceNetwork: true, resetting: true)
        state.isRefreshing = false
    }

    /// Standard lifecycle — pages using the last visible entry when available.
    func loadMore() async {
        guard let currentID = state.visibleEntries.last?.id else { return }
        await loadMoreIfNeeded(currentID: currentID)
    }

    func loadMoreIfNeeded(currentID: String) async {
        guard state.hasMore, !state.isLoadingMore, state.phase == .loaded else { return }
        guard state.visibleEntries.last?.id == currentID else { return }
        state.isLoadingMore = true
        await performBootstrap(forceNetwork: true, resetting: false)
        state.isLoadingMore = false
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

    func setScope(_ next: FeedScope) {
        guard state.scope != next else { return }
        ExperienceHaptics.play(.selection)
        state.scope = next
        if next == .global {
            state.stories = []
        }
        bootstrapTask?.cancel()
        bootstrapTask = Task { await performBootstrap(forceNetwork: true, resetting: true) }
    }

    func setContentFilter(_ next: FeedContentFilter) {
        guard state.contentFilter != next else { return }
        ExperienceHaptics.play(.selection)
        state.contentFilter = next
    }

    func open(_ entry: FeedTimelineEntry) {
        ExperienceHaptics.play(.selection)
        switch entry {
        case .trade(_, let trade):
            detailCache.seed(trade)
            navigationCoordinator.open(.feed(.trade(trade.id)))
        case .post(_, let post):
            detailCache.seed(post)
            navigationCoordinator.open(.feed(.post(post.id)))
        case .clip(_, let reel):
            detailCache.seed(reel)
            navigationCoordinator.open(.feed(.reel(reel.id)))
        case .achievement(_, let achievement):
            detailCache.seed(achievement)
            navigationCoordinator.open(.feed(.achievement(achievement.id)))
        }
    }

    func openAuthor(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.feed(.profile(profileID)))
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

    // MARK: - Bootstrap

    private func performBootstrap(forceNetwork _: Bool, resetting: Bool) async {
        if resetting {
            state.phase = state.entries.isEmpty ? .loading : state.phase
            state.nextCursor = nil
            state.hasMore = true
        }

        let context = FeedBootstrap.Context(
            feed: feed,
            trades: trades,
            profiles: profiles,
            achievements: achievements,
            session: session,
            detailCache: detailCache,
            scope: state.scope,
            cursor: resetting ? nil : state.nextCursor
        )

        do {
            let page: FeedBootstrap.PageResult
            if resetting {
                page = try await FeedBootstrap.loadInitial(context)
            } else {
                page = try await FeedBootstrap.loadMore(context)
            }
            guard !Task.isCancelled else { return }

            state.viewerID = page.viewerID
            if resetting {
                state.entries = page.entries
                state.stories = page.stories
            } else {
                let existing = Set(state.entries.map(\.id))
                let appended = page.entries.filter { !existing.contains($0.id) }
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
            await startRealtimeIfNeeded()
        } catch {
            if state.entries.isEmpty {
                state.phase = .failed(FeedSupport.message(for: error))
            } else {
                state.phase = .loaded
            }
        }
        bootstrapTask = nil
    }

    private func prefetchEngagement() {
        let targets: [InteractionTarget] = state.visibleEntries.compactMap { entry in
            switch entry {
            case .trade(_, let trade): return .trade(trade.id)
            case .post(_, let post): return .profilePost(post.id)
            case .clip(_, let reel): return .reel(reel.id)
            case .achievement(_, let achievement): return .achievement(achievement.id)
            }
        }
        engagementStore.prefetch(targets)
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
