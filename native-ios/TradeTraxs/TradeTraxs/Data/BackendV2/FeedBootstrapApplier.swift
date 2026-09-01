import Foundation

/// Maps `FeedBootstrapV1` RPC rows into native Feed presentation models.
enum FeedBootstrapApplier {
    struct Applied: Sendable {
        var items: [FeedItem]
        var stories: [Story]
        var engagementByTarget: [InteractionTarget: EngagementSnapshot]
        var nextCursor: String?
    }

    static func apply(_ bootstrap: FeedBootstrapV1) -> Applied {
        let authors = bootstrap.data.authors
        let engagementMap = bootstrap.data.engagement
        var items: [FeedItem] = []
        items.reserveCapacity(bootstrap.data.items.count)

        for row in bootstrap.data.items {
            if let item = mapItem(row, authors: authors, engagement: engagementMap) {
                items.append(item)
            }
        }

        let stories = bootstrap.data.stories.compactMap { preview -> Story? in
            guard let created = ISO8601.date(from: preview.created_at) else { return nil }
            return Story(
                id: StoryID(preview.id),
                authorProfileID: ProfileID(preview.user_id),
                media: MediaReference(id: preview.image_url, kind: .image, altText: nil),
                expiresAt: created.addingTimeInterval(86_400),
                createdAt: created,
                viewerHasSeen: false
            )
        }

        var engagementByTarget: [InteractionTarget: EngagementSnapshot] = [:]
        for row in bootstrap.data.items {
            guard let snap = engagementMap[row.id] else { continue }
            if let target = interactionTarget(for: row) {
                engagementByTarget[target] = EngagementSnapshot(
                    likeCount: snap.like_count,
                    commentCount: snap.comment_count,
                    viewerHasLiked: snap.liked_by_viewer
                )
            }
        }

        return Applied(
            items: items,
            stories: stories,
            engagementByTarget: engagementByTarget,
            nextCursor: bootstrap.data.next_cursor
        )
    }

    private static func mapItem(
        _ row: FeedItemV1,
        authors: [String: AuthorCardV1],
        engagement: [String: EngagementSnapshotV1]
    ) -> FeedItem? {
        guard let created = ISO8601.date(from: row.created_at) else { return nil }
        let author = authors[row.author_id]
        let eng = engagement[row.id]
        let kind = feedItemKind(row.kind)
        var item = FeedItem(
            id: row.id,
            kind: kind,
            authorProfileID: ProfileID(row.author_id),
            createdAt: created,
            tradeID: nil,
            postID: nil,
            reelID: nil,
            storyID: nil,
            achievementID: nil,
            caption: stringPayload(row.payload, keys: ["caption", "public_description", "body"]),
            likeCount: eng?.like_count ?? 0,
            commentCount: eng?.comment_count ?? 0,
            viewerHasLiked: eng?.liked_by_viewer ?? false,
            authorUsername: author?.username,
            authorDisplayName: author?.display_name ?? author?.username,
            authorAvatarURL: author?.avatar_url,
            mediaURL: stringPayload(row.payload, keys: ["image_url", "thumbnail_url", "media_url"])
        )
        switch kind {
        case .trade:
            item.tradeID = TradeID(stringPayload(row.payload, keys: ["trade_id"]) ?? row.id)
            item.caption = stringPayload(row.payload, keys: ["public_description"])
                ?? nestedString(row.payload, objectKey: "trades", keys: ["public_description"])
            item.mediaURL = stringPayload(row.payload, keys: ["image_url"])
        case .post:
            item.postID = PostID(row.id)
            item.caption = stringPayload(row.payload, keys: ["content", "body"])
            item.mediaURL = stringPayload(row.payload, keys: ["image_url"])
        case .reel:
            item.reelID = ReelID(row.id)
            item.caption = stringPayload(row.payload, keys: ["caption"])
            item.mediaURL = stringPayload(row.payload, keys: ["thumbnail_url", "image_url"])
        case .achievement:
            item.achievementID = AchievementID(
                stringPayload(row.payload, keys: ["achievement_id"]) ?? row.id
            )
            item.caption = stringPayload(row.payload, keys: ["title"])
                ?? nestedString(row.payload, objectKey: "achievements", keys: ["title"])
            item.mediaURL = stringPayload(row.payload, keys: ["image_url"])
                ?? nestedString(row.payload, objectKey: "achievements", keys: ["image_url"])
        case .story:
            item.storyID = StoryID(row.id)
        }
        return item
    }

    static func feedItemKind(_ raw: String) -> FeedItemKind {
        switch raw {
        case "profile_post": return .post
        case "achievement_post": return .achievement
        case "reel": return .reel
        case "post", "trade_card": return .trade
        default: return .trade
        }
    }

    private static func interactionTarget(for row: FeedItemV1) -> InteractionTarget? {
        switch feedItemKind(row.kind) {
        case .trade: return .feedPost(PostID(row.id))
        case .post: return .profilePost(PostID(row.id))
        case .reel: return .reel(ReelID(row.id))
        case .achievement: return .achievement(AchievementID(row.id))
        case .story: return nil
        }
    }

    private static func stringPayload(_ payload: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if case .string(let value) = payload[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func nestedString(
        _ payload: [String: JSONValue],
        objectKey: String,
        keys: [String]
    ) -> String? {
        guard case .object(let nested) = payload[objectKey] else { return nil }
        return stringPayload(nested, keys: keys)
    }
}
