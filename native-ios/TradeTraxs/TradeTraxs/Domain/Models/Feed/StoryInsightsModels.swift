import Foundation

nonisolated struct StoryInsights: Hashable, Sendable {
    var storyID: StoryID
    var viewCount: Int
    var likeCount: Int
    var replyCount: Int
    var viewers: [StoryInsightsViewer]
}

nonisolated struct StoryInsightsViewer: Hashable, Sendable, Identifiable {
    var id: ProfileID
    var username: String
    var displayName: String
    var avatarURL: String?
    var viewedAt: Date?
    var liked: Bool
    var replied: Bool

    var profileStub: Profile {
        let trimmedAvatar = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarRef: MediaReference? = {
            guard let trimmedAvatar, !trimmedAvatar.isEmpty else { return nil }
            return MediaReference(id: trimmedAvatar, kind: .image, altText: nil)
        }()
        return Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: username,
            displayName: displayName,
            bio: nil,
            avatar: avatarRef,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: viewedAt ?? .distantPast
        )
    }
}