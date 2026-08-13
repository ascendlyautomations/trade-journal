import Foundation

/// Ranked public trader for Explore discovery (not a separate social graph entity).
nonisolated struct ExploreTraderSuggestion: Hashable, Codable, Sendable, Identifiable {
    var id: ProfileID { profile.id }
    var profile: Profile
    var followerCount: Int
    var score: Int
    /// Identity line from real profile fields (type / style / market) — never invented reasons.
    var identityLine: String?
}

/// Public Trade Room surfaced for discovery.
nonisolated struct ExploreRoomSuggestion: Hashable, Codable, Sendable, Identifiable {
    var id: RoomID
    var name: String
    var slug: String
    var description: String?
    var memberCount: Int
    var imageURL: String?
}

nonisolated struct ExploreSocialCounts: Hashable, Sendable {
    var followers: [ProfileID: Int]
    var following: [ProfileID: Int]

    static let empty = ExploreSocialCounts(followers: [:], following: [:])
}

nonisolated struct ExploreSearchBundle: Hashable, Sendable {
    var people: [ExploreTraderSuggestion]
    var rooms: [ExploreRoomSuggestion]
}
