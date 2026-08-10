import Foundation

/// Mixed Home Feed samples for development / screenshots — reuses Profile section fixtures.
enum FeedFixtures {
    static let viewerID = ProfileID("dev.viewer")

    private static let avatarBase =
        "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=256&q=80"
    private static let storyMediaURL =
        "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"

    static func timeline(viewerID: ProfileID = viewerID) -> [FeedTimelineEntry] {
        let peer = ProfileID("dev.follower.ada")
        let trades = ProfileTradeFixtures.samples(owner: peer)
        let posts = ProfilePostFixtures.samples(owner: viewerID)
        let clips = ProfileClipFixtures.samples(owner: peer)
        let achievements = ProfileAchievementFixtures.samples(owner: viewerID)

        var entries: [FeedTimelineEntry] = []

        if let trade = trades.first {
            entries.append(
                .trade(
                    feedItem(
                        id: "feed-\(trade.id.rawValue)",
                        kind: .trade,
                        authorProfileID: trade.ownerProfileID,
                        createdAt: trade.createdAt,
                        tradeID: trade.id,
                        caption: trade.publicCaption,
                        mediaURL: trade.thumbnail?.id
                    ),
                    trade
                )
            )
        }

        for post in posts.prefix(2) {
            entries.append(
                .post(
                    feedItem(
                        id: "feed-\(post.id.rawValue)",
                        kind: .post,
                        authorProfileID: post.authorProfileID,
                        createdAt: post.createdAt,
                        postID: post.id,
                        caption: post.body,
                        mediaURL: post.media.first?.id
                    ),
                    post
                )
            )
        }

        // Explicit text-only post for Layout B screenshots / filter parity.
        if let textOnly = posts.first(where: { $0.media.isEmpty }) {
            let already = entries.contains {
                if case .post(_, let post) = $0 { return post.id == textOnly.id }
                return false
            }
            if !already {
                entries.append(
                    .post(
                        feedItem(
                            id: "feed-\(textOnly.id.rawValue)",
                            kind: .post,
                            authorProfileID: textOnly.authorProfileID,
                            createdAt: textOnly.createdAt,
                            postID: textOnly.id,
                            caption: textOnly.body,
                            mediaURL: nil
                        ),
                        textOnly
                    )
                )
            }
        }

        if let clip = clips.first {
            entries.append(
                .clip(
                    feedItem(
                        id: "feed-\(clip.id.rawValue)",
                        kind: .reel,
                        authorProfileID: clip.authorProfileID,
                        createdAt: clip.createdAt,
                        tradeID: clip.linkedTradeID,
                        reelID: clip.id,
                        caption: clip.caption,
                        mediaURL: clip.thumbnail?.id ?? clip.video.id
                    ),
                    clip
                )
            )
        }

        if let achievement = achievements.first {
            entries.append(
                .achievement(
                    feedItem(
                        id: "feed-\(achievement.id.rawValue)",
                        kind: .achievement,
                        authorProfileID: achievement.ownerProfileID,
                        createdAt: achievement.achievedAt,
                        achievementID: achievement.id,
                        caption: achievement.title,
                        mediaURL: achievement.image?.id
                    ),
                    achievement
                )
            )
        }

        // Second trade + post for a longer Instagram-style scroll.
        if trades.count > 1 {
            let trade = trades[1]
            entries.append(
                .trade(
                    feedItem(
                        id: "feed-\(trade.id.rawValue)",
                        kind: .trade,
                        authorProfileID: trade.ownerProfileID,
                        createdAt: trade.createdAt.addingTimeInterval(-120),
                        tradeID: trade.id,
                        caption: trade.publicCaption,
                        mediaURL: trade.thumbnail?.id
                    ),
                    trade
                )
            )
        }

        return FeedSupport.sortDescending(entries)
    }

    /// Builds a FeedItem with the same author fields the web `profiles(...)` embed provides.
    static func feedItem(
        id: String,
        kind: FeedItemKind,
        authorProfileID: ProfileID,
        createdAt: Date,
        tradeID: TradeID? = nil,
        postID: PostID? = nil,
        reelID: ReelID? = nil,
        achievementID: AchievementID? = nil,
        caption: String?,
        mediaURL: String?
    ) -> FeedItem {
        let author = authorProfiles(including: viewerID)
            .first { $0.id == authorProfileID }
            ?? FollowListFixtures.profile(id: authorProfileID)
        return FeedItem(
            id: id,
            kind: kind,
            authorProfileID: authorProfileID,
            createdAt: createdAt,
            tradeID: tradeID,
            postID: postID,
            reelID: reelID,
            storyID: nil,
            achievementID: achievementID,
            caption: caption,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            authorUsername: author?.username,
            authorDisplayName: author?.displayName ?? author?.username,
            authorAvatarURL: author?.avatar?.id,
            mediaURL: mediaURL
        )
    }

    /// Stories row samples — one request path via `FeedRepository.stories` in production.
    static func stories(viewerID: ProfileID = viewerID) -> [Story] {
        let now = Date()
        let authors: [(ProfileID, Bool)] = [
            (ProfileID("dev.follower.ada"), false),
            (ProfileID("dev.following.nq"), false),
            (ProfileID("dev.following.ict"), true),
            (ProfileID("dev.follower.grace"), false),
            (viewerID, true),
        ]
        return authors.enumerated().map { index, pair in
            Story(
                id: StoryID("dev-story-\(index + 1)"),
                authorProfileID: pair.0,
                media: MediaReference(
                    id: storyMediaURL,
                    kind: .image,
                    altText: "Story media"
                ),
                expiresAt: now.addingTimeInterval(86_400),
                createdAt: now.addingTimeInterval(TimeInterval(-600 * (index + 1))),
                viewerHasSeen: pair.1
            )
        }
    }

    static func seedDetailCache(_ cache: DetailPresentationCache, viewerID: ProfileID = viewerID) {
        let entries = timeline(viewerID: viewerID)
        for entry in entries {
            switch entry {
            case .trade(_, let trade):
                cache.seed(trade)
            case .post(_, let post):
                cache.seed(post)
            case .clip(_, let reel):
                cache.seed(reel)
            case .achievement(_, let achievement):
                cache.seed(achievement)
            }
        }

        for profile in authorProfiles(including: viewerID) {
            cache.seed(profile)
        }

        let storyItems = stories(viewerID: viewerID)
        cache.seed(stories: storyItems)
    }

    /// Fixture authors with avatars — seeded once into DetailPresentationCache (no N+1).
    static func authorProfiles(including viewerID: ProfileID) -> [Profile] {
        let owner = ProfileID("dev.fixture-owner")
        var profiles = FollowListFixtures.followers(owner: owner)
            + FollowListFixtures.following(owner: owner)
        profiles.append(
            Profile(
                id: viewerID,
                userID: UserID(viewerID.rawValue),
                username: "you",
                displayName: "You",
                bio: nil,
                avatar: MediaReference(id: avatarBase, kind: .image, altText: "You"),
                traderType: .futures,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        return profiles.enumerated().map { index, profile in
            var copy = profile
            if copy.avatar == nil {
                copy.avatar = MediaReference(
                    id: "https://i.pravatar.cc/256?u=\(profile.id.rawValue)&\(index)",
                    kind: .image,
                    altText: profile.displayName
                )
            }
            return copy
        }
    }
}
