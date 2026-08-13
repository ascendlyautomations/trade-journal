import Foundation

/// Web `lib/activeStories.ts` — rolling 24h window from `created_at` (UTC epoch ms).
///
/// Web: `nowMs - created < STORY_WINDOW_MS` and `Number.isNaN(created) → false`.
/// Native must not substitute `Date.distantPast` for unparseable timestamps.
enum ActiveStorySemantics {
    static let window: TimeInterval = 24 * 60 * 60

    static func isActive(createdAt: Date, now: Date = Date()) -> Bool {
        // Exact web: `nowMs - created < STORY_WINDOW_MS` (future timestamps remain active).
        now.timeIntervalSince(createdAt) < window
    }

    static func filterActive(_ stories: [Story], now: Date = Date()) -> [Story] {
        stories.filter { isActive(createdAt: $0.createdAt, now: now) }
    }

    /// One strip bubble per author (newest story), ordered like web bar:
    /// viewer first (if present), then others by newest story `created_at` desc.
    static func stripStories(from active: [Story], viewerID: ProfileID) -> [Story] {
        var newestByAuthor: [ProfileID: Story] = [:]
        for story in active {
            if let existing = newestByAuthor[story.authorProfileID] {
                if story.createdAt > existing.createdAt {
                    newestByAuthor[story.authorProfileID] = story
                }
            } else {
                newestByAuthor[story.authorProfileID] = story
            }
        }

        var others = newestByAuthor.values
            .filter { $0.authorProfileID != viewerID }
            .sorted { $0.createdAt > $1.createdAt }

        if let mine = newestByAuthor[viewerID] {
            return [mine] + others
        }
        return others
    }
}
