import Foundation

/// Feed / detail share entry — one picker + send flow for all structured content types.
struct SharedContentShareTarget: Identifiable, Equatable, Sendable {
    var reference: SharedContentReference
    var contentLink: DetailContentLink
    var shareTitle: String
    var externalShareText: String
    /// Feed trade cards can use native room `trade_id` inserts when available.
    var roomTradeID: TradeID?

    var id: String {
        switch reference {
        case .feedPost(let id): return "feedPost:\(id.rawValue)"
        case .profilePost(let id): return "profilePost:\(id.rawValue)"
        case .achievementPost(let id): return "achievementPost:\(id.rawValue)"
        case .reel(let id): return "reel:\(id.rawValue)"
        case .trade(let id): return "trade:\(id.rawValue)"
        }
    }

    static func from(entry: FeedTimelineEntry, author: Profile?) -> SharedContentShareTarget {
        let handle = author.flatMap { profile in
            let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
            return username.isEmpty ? nil : "@\(username)"
        } ?? "A trader"

        switch entry {
        case .trade(let item, let summary):
            return SharedContentShareTarget(
                reference: .feedPost(PostID(item.id)),
                contentLink: .post(PostID(item.id)),
                shareTitle: "Share Trade",
                externalShareText: "\(handle)'s trade on TradeTraxs",
                roomTradeID: summary.id
            )
        case .post(let item, _):
            return SharedContentShareTarget(
                reference: .profilePost(PostID(item.id)),
                contentLink: .post(PostID(item.id)),
                shareTitle: "Share Post",
                externalShareText: "\(handle)'s post on TradeTraxs",
                roomTradeID: nil
            )
        case .clip(_, let reel):
            return SharedContentShareTarget(
                reference: .reel(reel.id),
                contentLink: .reel(reel.id),
                shareTitle: "Share Clip",
                externalShareText: "\(handle)'s clip on TradeTraxs",
                roomTradeID: nil
            )
        case .achievement(let item, let achievement):
            let title = achievement.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = title.isEmpty ? "an achievement" : "“\(title)”"
            return SharedContentShareTarget(
                reference: .achievementPost(PostID(item.id)),
                contentLink: .achievement(AchievementID(item.id)),
                shareTitle: "Share Achievement",
                externalShareText: "\(handle) shared \(suffix) on TradeTraxs",
                roomTradeID: nil
            )
        }
    }
}
