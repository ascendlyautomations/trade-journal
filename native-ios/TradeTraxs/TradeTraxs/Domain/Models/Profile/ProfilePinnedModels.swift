import Foundation

/// Cross-type Profile showcase pin — maps to `profile_pinned_content.content_type`.
nonisolated enum ProfilePinnedContentType: String, Hashable, Codable, Sendable {
    case trade
    case profilePost = "profile_post"
    case achievement

    static func parse(_ raw: String?) -> ProfilePinnedContentType? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "trade": return .trade
        case "profile_post", "post": return .profilePost
        case "achievement": return .achievement
        default: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .trade: return "Trade"
        case .profilePost: return "Post"
        case .achievement: return "Achievement"
        }
    }
}

nonisolated struct ProfilePinnedPreview: Hashable, Codable, Sendable {
    var kindLabel: String
    var title: String
    var subtitle: String?
    var imageURL: String?
    var body: String?
    var valueText: String?

    var imageReference: MediaReference? {
        guard let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return MediaReference(id: raw, kind: .image, altText: nil)
    }
}

nonisolated struct ProfilePinnedItem: Hashable, Codable, Sendable, Identifiable {
    var contentType: ProfilePinnedContentType
    var contentID: String
    var position: Int
    var preview: ProfilePinnedPreview

    var id: String { "\(contentType.rawValue):\(contentID)" }

    var tradeID: TradeID? {
        contentType == .trade ? TradeID(contentID) : nil
    }

    var postID: PostID? {
        contentType == .profilePost ? PostID(contentID) : nil
    }

    var achievementID: AchievementID? {
        contentType == .achievement ? AchievementID(contentID) : nil
    }
}

nonisolated struct ProfilePinRequest: Sendable {
    var contentType: ProfilePinnedContentType
    var contentID: String
    var replacePosition: Int?
}

enum ProfilePinnedPreviewBuilder {
    static func from(trade: Trade) -> ProfilePinnedPreview {
        ProfilePinnedPreview(
            kindLabel: "Trade",
            title: TradeDisplay.pnlText(trade.realizedPnL),
            subtitle: "\(trade.symbol.ticker) · \(TradeDisplay.sideTitle(trade.side))",
            imageURL: trade.thumbnail?.id,
            body: trade.notePreview,
            valueText: nil
        )
    }

    static func from(post: Post) -> ProfilePinnedPreview {
        let body = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProfilePinnedPreview(
            kindLabel: "Post",
            title: String(body.prefix(120)),
            subtitle: nil,
            imageURL: post.media.first?.id,
            body: body,
            valueText: nil
        )
    }

    static func from(achievement: Achievement) -> ProfilePinnedPreview {
        ProfilePinnedPreview(
            kindLabel: "Achievement",
            title: achievement.title,
            subtitle: achievement.firm ?? achievement.kind.displayName,
            imageURL: achievement.image?.id,
            body: achievement.description,
            valueText: achievement.value.map { TradeDisplay.pnlText($0) } ?? achievement.valueText
        )
    }
}

extension ProfilePinnedContentType {
    static func from(trade: Trade) -> ProfilePinnedContentType { .trade }
    static func from(post: Post) -> ProfilePinnedContentType { .profilePost }
    static func from(achievement: Achievement) -> ProfilePinnedContentType { .achievement }
}

extension AchievementKind {
    var displayName: String {
        switch self {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Passed Eval"
        case .milestone: return "Milestone"
        }
    }
}
