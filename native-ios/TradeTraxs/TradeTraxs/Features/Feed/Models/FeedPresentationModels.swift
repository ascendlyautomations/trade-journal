import Foundation

/// Web `FeedContentFilter` — All / Trades / Posts / Clips / Achievements.
enum FeedContentFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case trades
    case posts
    case clips
    case achievements

    var title: String {
        switch self {
        case .all: return "All"
        case .trades: return "Trades"
        case .posts: return "Posts"
        case .clips: return "Clips"
        case .achievements: return "Achievements"
        }
    }

    /// Compact monochrome SF Symbol for the feed filter strip.
    var icon: AppIcon {
        switch self {
        case .all: return .grid
        case .trades: return .chart
        case .posts: return .textBubble
        case .clips: return .playRectangle
        case .achievements: return .trophy
        }
    }
}

/// Hydrated feed row — wraps domain models already used by Profile cards / Detail.
enum FeedTimelineEntry: Identifiable, Hashable, Sendable {
    case trade(FeedItem, Trade)
    case post(FeedItem, Post)
    case clip(FeedItem, Reel)
    case achievement(FeedItem, Achievement)

    var id: String {
        switch self {
        case .trade(let item, _): return item.id
        case .post(let item, _): return item.id
        case .clip(let item, _): return item.id
        case .achievement(let item, _): return item.id
        }
    }

    var item: FeedItem {
        switch self {
        case .trade(let item, _), .post(let item, _), .clip(let item, _), .achievement(let item, _):
            return item
        }
    }

    var createdAt: Date { item.createdAt }

    var authorProfileID: ProfileID { item.authorProfileID }

    var matches: FeedContentFilter {
        switch self {
        case .trade: return .trades
        case .post: return .posts
        case .clip: return .clips
        case .achievement: return .achievements
        }
    }

    func matches(filter: FeedContentFilter) -> Bool {
        filter == .all || matches == filter
    }

    /// Whether the row should use Layout A (media). False → Layout B (text-first, no placeholder).
    var hasDisplayMedia: Bool {
        switch self {
        case .trade(_, let trade):
            return trade.thumbnail != nil
        case .post(_, let post):
            return post.media.contains {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .clip(_, let reel):
            let thumb = reel.thumbnail?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let video = reel.video.id.trimmingCharacters(in: .whitespacesAndNewlines)
            return !thumb.isEmpty || !video.isEmpty
        case .achievement(_, let achievement):
            return achievement.image != nil
        }
    }
}

enum FeedSupport {
    static func isLocalDevelopmentProfile(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
    }

    static func message(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return UserFacingError.map(AppError.unknown(message: error.localizedDescription)).message
    }

    /// Web `sortFeedItemsDesc` — newest `created_at` first.
    static func sortDescending(_ entries: [FeedTimelineEntry]) -> [FeedTimelineEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }
}
