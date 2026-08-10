import Foundation
import Observation

@Observable
@MainActor
final class FeedViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var entries: [FeedTimelineEntry] = []
    private(set) var stories: [Story] = []
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var viewerID: ProfileID?
    var scope: FeedScope = .following
    var contentFilter: FeedContentFilter = .all

    private let feed: any FeedRepository
    private let trades: any TradeRepository
    private let profiles: any ProfileRepository
    private let achievements: any AchievementRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?

    private var nextCursor: String?
    private var hasMore = true
    private var loadTask: Task<Void, Never>?
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

    var visibleEntries: [FeedTimelineEntry] {
        entries.filter { $0.matches(filter: contentFilter) }
    }

    var showsEmpty: Bool {
        phase == .loaded && visibleEntries.isEmpty
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded else { return }
        loadTask = Task { await performLoad(forceNetwork: false, resetting: true) }
    }

    func refresh() async {
        loadTask?.cancel()
        isRefreshing = true
        await performLoad(forceNetwork: true, resetting: true)
        isRefreshing = false
    }

    func loadMoreIfNeeded(currentID: String) async {
        guard hasMore, !isLoadingMore, phase == .loaded else { return }
        guard visibleEntries.last?.id == currentID else { return }
        isLoadingMore = true
        await performLoad(forceNetwork: true, resetting: false)
        isLoadingMore = false
    }

    func setScope(_ next: FeedScope) {
        guard scope != next else { return }
        ExperienceHaptics.play(.selection)
        scope = next
        loadTask?.cancel()
        loadTask = Task { await performLoad(forceNetwork: true, resetting: true) }
    }

    func setContentFilter(_ next: FeedContentFilter) {
        guard contentFilter != next else { return }
        ExperienceHaptics.play(.selection)
        contentFilter = next
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
        // Existing story experience — full-screen cover destination.
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

    // MARK: - Private

    private func performLoad(forceNetwork: Bool, resetting: Bool) async {
        if resetting {
            phase = entries.isEmpty ? .loading : phase
            nextCursor = nil
            hasMore = true
        }

        let current = await session.currentUserID
        let viewer = current.map { ProfileID($0.rawValue) }
        viewerID = viewer

        if let viewer, FeedSupport.isLocalDevelopmentProfile(viewer) {
            FeedFixtures.seedDetailCache(detailCache, viewerID: viewer)
            entries = FeedFixtures.timeline(viewerID: viewer)
            stories = FeedFixtures.stories(viewerID: viewer)
            prefetchEngagement()
            phase = .loaded
            hasMore = false
            await startRealtimeIfNeeded()
            loadTask = nil
            return
        }

        do {
            var page = PageRequest(limit: 20)
            if !resetting {
                page.cursor = nextCursor
            }
            let result = try await feed.feed(scope: scope, page: page)
            let hydrated = await hydrate(result.items)
            if resetting {
                entries = FeedSupport.sortDescending(hydrated)
            } else {
                let existing = Set(entries.map(\.id))
                let appended = hydrated.filter { !existing.contains($0.id) }
                entries = FeedSupport.sortDescending(entries + appended)
            }
            nextCursor = result.nextCursor
            hasMore = result.nextCursor != nil
            if resetting, let viewer {
                await loadStories(for: viewer)
            }
            prefetchEngagement()
            phase = .loaded
            await startRealtimeIfNeeded()
        } catch {
            if entries.isEmpty {
                phase = .failed(FeedSupport.message(for: error))
            } else {
                phase = .loaded
            }
        }
        loadTask = nil
    }

    /// Single stories request for the strip — not per feed item.
    private func loadStories(for viewer: ProfileID) async {
        guard let loaded = try? await feed.stories(for: viewer) else { return }
        stories = loaded
        detailCache.seed(stories: loaded)
        // Authors already in cache (following / prior detail) — never N+1 fetch here.
        for story in loaded {
            if detailCache.profile(id: story.authorProfileID) == nil,
               let fixture = FollowListFixtures.profile(id: story.authorProfileID)
            {
                detailCache.seed(fixture)
            }
        }
    }

    private func hydrate(_ items: [FeedItem]) async -> [FeedTimelineEntry] {
        var result: [FeedTimelineEntry] = []
        result.reserveCapacity(items.count)
        for item in items {
            seedAuthor(from: item)
            if let entry = await hydrateOne(item) {
                result.append(entry)
            }
        }
        return result
    }

    /// Seeds authors from the web feed `profiles(...)` embed already on each `FeedItem`.
    /// Never calls `profiles.profile(id:)` per row — avoids N+1.
    private func seedAuthor(from item: FeedItem) {
        if let username = item.authorUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty
        {
            let display = item.authorDisplayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let avatarURL = item.authorAvatarURL?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = detailCache.profile(id: item.authorProfileID)
            detailCache.seed(
                Profile(
                    id: item.authorProfileID,
                    userID: existing?.userID ?? UserID(item.authorProfileID.rawValue),
                    username: username,
                    displayName: (display?.isEmpty == false) ? display! : username,
                    bio: existing?.bio,
                    avatar: {
                        if let avatarURL, !avatarURL.isEmpty {
                            return MediaReference(id: avatarURL, kind: .image, altText: nil)
                        }
                        return existing?.avatar
                    }(),
                    traderType: existing?.traderType,
                    tradingStyle: existing?.tradingStyle,
                    primaryMarket: existing?.primaryMarket,
                    startedTradingAt: existing?.startedTradingAt,
                    isPrivate: existing?.isPrivate ?? false,
                    isCreator: existing?.isCreator ?? false,
                    createdAt: existing?.createdAt ?? item.createdAt
                )
            )
            return
        }
        if detailCache.profile(id: item.authorProfileID) != nil { return }
        if let fixture = FollowListFixtures.profile(id: item.authorProfileID) {
            detailCache.seed(fixture)
        }
    }

    private func hydrateOne(_ item: FeedItem) async -> FeedTimelineEntry? {
        switch item.kind {
        case .trade:
            guard let tradeID = item.tradeID else { return nil }
            if let cached = detailCache.trade(id: tradeID) {
                return .trade(item, cached)
            }
            if let trade = try? await trades.trade(id: tradeID) {
                detailCache.seed(trade)
                return .trade(item, trade)
            }
            return nil

        case .post:
            guard let postID = item.postID else { return nil }
            if let cached = detailCache.post(id: postID) {
                return .post(item, cached)
            }
            // Web profile_posts row is already on the FeedItem — no second fetch required.
            if item.caption != nil || item.mediaURL != nil {
                let media: [MediaReference] = {
                    guard let url = item.mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !url.isEmpty else { return [] }
                    return [MediaReference(id: url, kind: .image, altText: nil)]
                }()
                let post = Post(
                    id: postID,
                    authorProfileID: item.authorProfileID,
                    body: item.caption ?? "",
                    media: media,
                    visibility: .public,
                    linkedTradeID: item.tradeID,
                    isPinned: false,
                    createdAt: item.createdAt,
                    updatedAt: item.createdAt
                )
                detailCache.seed(post)
                return .post(item, post)
            }
            if let post = try? await profiles.wallPost(id: postID) {
                detailCache.seed(post)
                return .post(item, post)
            }
            return nil

        case .reel:
            guard let reelID = item.reelID else { return nil }
            if let cached = detailCache.reel(id: reelID) {
                return .clip(item, cached)
            }
            if let reel = try? await feed.reel(id: reelID) {
                detailCache.seed(reel)
                return .clip(item, reel)
            }
            // Fallback from feed row media when reel detail fetch is unavailable.
            if let media = item.mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !media.isEmpty
            {
                let reel = Reel(
                    id: reelID,
                    authorProfileID: item.authorProfileID,
                    video: MediaReference(id: media, kind: .video, altText: nil),
                    thumbnail: MediaReference(id: media, kind: .image, altText: nil),
                    caption: item.caption,
                    visibility: .public,
                    linkedTradeID: item.tradeID,
                    durationSeconds: nil,
                    createdAt: item.createdAt
                )
                detailCache.seed(reel)
                return .clip(item, reel)
            }
            return nil

        case .achievement:
            guard let achievementID = item.achievementID else { return nil }
            if let cached = detailCache.achievement(id: achievementID) {
                return .achievement(item, cached)
            }
            if let achievement = try? await achievements.achievement(id: achievementID) {
                detailCache.seed(achievement)
                return .achievement(item, achievement)
            }
            return nil

        case .story:
            return nil
        }
    }

    private func prefetchEngagement() {
        let targets: [InteractionTarget] = visibleEntries.compactMap { entry in
            switch entry {
            case .trade(_, let trade): return .trade(trade.id)
            case .post(_, let post): return .profilePost(post.id)
            case .clip(_, let reel): return .reel(reel.id)
            case .achievement(_, let achievement): return .achievement(achievement.id)
            }
        }
        engagementStore.prefetch(targets)
    }

    /// Event-driven only — subscribe + idle until postgres_changes arrive. No polling.
    private func startRealtimeIfNeeded() async {
        guard let realtimeHub else { return }
        guard let viewerID, !FeedSupport.isLocalDevelopmentProfile(viewerID) else { return }
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
            entries.removeAll { $0.item.postID?.rawValue == raw || $0.id == raw }
        case .insert, .update:
            guard let raw = signal.messageID else { return }
            let postID = PostID(raw)
            // Single-row hydrate — never reload the full feed.
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
            seedAuthor(from: item)
            if let hydrated = await hydrateOne(item) {
                upsert(hydrated)
                prefetchEngagement()
            }
        }
    }

    private func upsert(_ entry: FeedTimelineEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries = FeedSupport.sortDescending(entries)
    }
}
