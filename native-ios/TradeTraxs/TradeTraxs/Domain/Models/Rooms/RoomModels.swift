import Foundation

nonisolated enum RoomMemberRole: String, Hashable, Codable, Sendable {
    case owner
    case admin
    case member
}

nonisolated enum RoomModerationAction: String, Hashable, Codable, Sendable {
    case pin
    case mute
    case remove
    case ban
}

nonisolated struct TradeRoom: Hashable, Codable, Sendable, Identifiable {
    var id: RoomID
    var ownerProfileID: ProfileID
    var name: String
    var slug: String
    var description: String?
    var image: MediaReference?
    var memberCount: Int
    var showsOnProfile: Bool
    var createdAt: Date
}

nonisolated struct RoomMembership: Hashable, Codable, Sendable {
    var roomID: RoomID
    var profileID: ProfileID
    var role: RoomMemberRole
    var joinedAt: Date
    var notificationsEnabled: Bool
}

nonisolated struct RoomMessage: Hashable, Codable, Sendable, Identifiable {
    var id: RoomMessageID
    var roomID: RoomID
    var senderProfileID: ProfileID
    var body: String?
    var attachedTradeID: TradeID?
    var media: [MediaReference]
    var parentMessageID: RoomMessageID?
    var isPinned: Bool
    var createdAt: Date
}
