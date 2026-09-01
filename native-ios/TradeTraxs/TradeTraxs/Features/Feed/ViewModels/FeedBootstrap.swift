import Foundation

/// Coordinated Feed first-paint / page load — owned exclusively by ``FeedScreenViewModel``.
///
/// Timeline and stories run concurrently. Stories failure never fails the timeline
/// (same product behavior as before; ownership is now explicit).
/// Conforms to ``ScreenBootstrap`` via ``load`` → ``loadInitial``.
@MainActor
enum FeedBootstrap: ScreenBootstrap {
    struct Context {
        var feed: any FeedRepository
        var trades: any TradeRepository
        var profiles: any ProfileRepository
        var achievements: any AchievementRepository
        var session: any SessionProviding
        var detailCache: DetailPresentationCache
        var scope: FeedScope
        var cursor: String?
        var limit: Int = 20
    }

    struct PageResult {
        var viewerID: ProfileID?
        var entries: [FeedTimelineEntry]
        var stories: [Story]
        var nextCursor: String?
        var usedDevelopmentFixtures: Bool
    }

    /// ``ScreenBootstrap`` entry — same as ``loadInitial``.
    static func load(_ context: Context) async throws -> PageResult {
        try await loadInitial(context)
    }

    /// Initial bootstrap or pull-to-refresh / scope change (resetting page).
    static func loadInitial(_ context: Context) async throws -> PageResult {
        let viewer = await context.session.currentUserID.map { ProfileID($0.rawValue) }

        if let viewer, FeedSupport.isLocalDevelopmentProfile(viewer) {
            FeedFixtures.seedDetailCache(context.detailCache, viewerID: viewer)
            return PageResult(
                viewerID: viewer,
                entries: FeedFixtures.timeline(viewerID: viewer),
                stories: context.scope == .following ? FeedFixtures.stories(viewerID: viewer) : [],
                nextCursor: nil,
                usedDevelopmentFixtures: true
            )
        }

        // Concurrent: timeline + stories (Following only). Stories must not block / fail timeline.
        async let timelineTask = loadTimeline(context)
        async let storiesTask = loadStories(viewer: viewer, context: context)

        let timeline = try await timelineTask
        let stories = await storiesTask

        return PageResult(
            viewerID: viewer,
            entries: timeline.entries,
            stories: stories,
            nextCursor: timeline.nextCursor,
            usedDevelopmentFixtures: false
        )
    }

    /// Pagination — timeline only (stories already on screen).
    static func loadMore(_ context: Context) async throws -> PageResult {
        let viewer = await context.session.currentUserID.map { ProfileID($0.rawValue) }
        let timeline = try await loadTimeline(context)
        return PageResult(
            viewerID: viewer,
            entries: timeline.entries,
            stories: [],
            nextCursor: timeline.nextCursor,
            usedDevelopmentFixtures: false
        )
    }

    // MARK: - Timeline

    private struct TimelinePage {
        var entries: [FeedTimelineEntry]
        var nextCursor: String?
    }

    private static func loadTimeline(_ context: Context) async throws -> TimelinePage {
        var page = PageRequest(limit: context.limit)
        page.cursor = context.cursor
        let result = try await context.feed.feed(scope: context.scope, page: page)
        if !result.embeddedTrades.isEmpty {
            context.detailCache.seed(trades: result.embeddedTrades)
        }
        let hydrated = await hydrate(
            result.items,
            feed: context.feed,
            trades: context.trades,
            profiles: context.profiles,
            achievements: context.achievements,
            detailCache: context.detailCache
        )
        return TimelinePage(
            entries: FeedSupport.sortDescending(hydrated),
            nextCursor: result.nextCursor
        )
    }

    private static func loadStories(viewer: ProfileID?, context: Context) async -> [Story] {
        guard let viewer else { return [] }
        guard context.scope == .following else {
            #if DEBUG
            StoriesLoadProbe.record(stage: "scope", detail: "skipped — global mode")
            #endif
            return []
        }

        do {
            let loaded = try await context.feed.stories(for: viewer)
            context.detailCache.seed(stories: loaded)
            await hydrateStoryAuthors(
                loaded,
                profiles: context.profiles,
                detailCache: context.detailCache
            )
            #if DEBUG
            StoriesLoadProbe.record(stage: "ui", detail: "assigned stories=\(loaded.count)")
            #endif
            return loaded
        } catch {
            #if DEBUG
            StoriesLoadProbe.record(stage: "error", detail: String(describing: error))
            #endif
            return []
        }
    }

    private static func hydrateStoryAuthors(
        _ loaded: [Story],
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache
    ) async {
        let unique = Array(Set(loaded.map(\.authorProfileID)))
        guard !unique.isEmpty else { return }
        for authorID in unique {
            if let fixture = FollowListFixtures.profile(id: authorID) {
                detailCache.seed(fixture)
            }
        }
        _ = try? await SessionProfileStore.shared.profiles(
            ids: unique,
            detailCache: detailCache,
            repository: profiles
        )
    }

    // MARK: - Hydration (unchanged query semantics)

    /// Builds timeline entries from RPC-seeded cache — no network (V2 bootstrap path).
    static func buildEntriesFromSeededItems(
        _ items: [FeedItem],
        detailCache: DetailPresentationCache
    ) -> [FeedTimelineEntry] {
        for item in items {
            seedAuthor(from: item, detailCache: detailCache)
        }
        var result: [FeedTimelineEntry] = []
        result.reserveCapacity(items.count)
        for item in items {
            switch item.kind {
            case .trade:
                guard let tradeID = item.tradeID,
                      let trade = detailCache.trade(id: tradeID)
                else { continue }
                result.append(.trade(item, trade))
            case .post:
                guard let postID = item.postID,
                      let post = detailCache.post(id: postID)
                else { continue }
                result.append(.post(item, post))
            case .reel:
                guard let reelID = item.reelID,
                      let reel = detailCache.reel(id: reelID)
                else { continue }
                result.append(.clip(item, reel))
            case .achievement:
                guard let achievementID = item.achievementID,
                      let achievement = detailCache.achievement(id: achievementID)
                else { continue }
                result.append(.achievement(item, achievement))
            case .story:
                continue
            }
        }
        return result
    }

    static func hydrate(
        _ items: [FeedItem],
        feed: any FeedRepository,
        trades: any TradeRepository,
        profiles: any ProfileRepository,
        achievements: any AchievementRepository,
        detailCache: DetailPresentationCache
    ) async -> [FeedTimelineEntry] {
        for item in items {
            seedAuthor(from: item, detailCache: detailCache)
        }

        let tradeIDs = items.compactMap { item -> TradeID? in
            guard item.kind == .trade, let id = item.tradeID else { return nil }
            return detailCache.trade(id: id) == nil ? id : nil
        }
        if !tradeIDs.isEmpty {
            _ = try? await SessionTradeEntityStore.shared.trades(
                ids: tradeIDs,
                detailCache: detailCache,
                repository: trades
            )
        }

        var result: [FeedTimelineEntry] = []
        result.reserveCapacity(items.count)
        for item in items {
            if let entry = await hydrateOne(
                item,
                feed: feed,
                trades: trades,
                profiles: profiles,
                achievements: achievements,
                detailCache: detailCache
            ) {
                result.append(entry)
            }
        }
        return result
    }

    /// Seeds author profiles from feed embeds (list + realtime). Never N+1 `profile(id:)`.
    static func seedAuthor(from item: FeedItem, detailCache: DetailPresentationCache) {
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

    static func hydrateOne(
        _ item: FeedItem,
        feed: any FeedRepository,
        trades: any TradeRepository,
        profiles: any ProfileRepository,
        achievements: any AchievementRepository,
        detailCache: DetailPresentationCache
    ) async -> FeedTimelineEntry? {
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
            if let reel = try? await feed.reel(id: reelID) {
                detailCache.seed(reel)
                return .clip(item, reel)
            }
            return nil

        case .achievement:
            guard let achievementID = item.achievementID else { return nil }
            if let cached = detailCache.achievement(id: achievementID) {
                return .achievement(item, cached)
            }
            if item.caption != nil || item.mediaURL != nil {
                let image: MediaReference? = {
                    guard let url = item.mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !url.isEmpty else { return nil }
                    return MediaReference(id: url, kind: .image, altText: nil)
                }()
                let achievement = Achievement(
                    id: achievementID,
                    ownerProfileID: item.authorProfileID,
                    kind: .milestone,
                    title: item.caption ?? "Achievement",
                    description: nil,
                    tier: .bronze,
                    value: nil,
                    valueText: nil,
                    firm: nil,
                    accountID: nil,
                    image: image,
                    isPublic: true,
                    isFeatured: false,
                    sortOrder: 0,
                    achievedAt: item.createdAt
                )
                detailCache.seed(achievement)
                return .achievement(item, achievement)
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
}
