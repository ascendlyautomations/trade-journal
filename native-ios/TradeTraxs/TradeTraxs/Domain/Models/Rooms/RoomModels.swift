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
    /// Active members (`left_at IS NULL`). Nil until batch-loaded or room detail fetch.
    var memberCount: Int?
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

/// Web `room_sections` row — a channel inside a Trade Room workspace.
nonisolated struct RoomChannel: Hashable, Codable, Sendable, Identifiable {
    var id: RoomChannelID
    var roomID: RoomID
    var name: String
    var position: Int
    var allowMembersChat: Bool

    /// Display label like `# general`.
    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "# channel" }
        if trimmed.hasPrefix("#") { return trimmed }
        return "# \(trimmed)"
    }

    var isGeneral: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "general"
    }
}

nonisolated struct RoomMessageReaction: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var messageID: RoomMessageID
    var userID: ProfileID
    var reaction: String
    var createdAt: Date?
}

nonisolated struct RoomMessageReactionSummary: Hashable, Sendable {
    var emoji: String
    var count: Int
    var reactedByViewer: Bool
}

nonisolated struct RoomMessage: Hashable, Codable, Sendable, Identifiable {
    var id: RoomMessageID
    var roomID: RoomID
    var senderProfileID: ProfileID
    var body: String?
    var attachedTradeID: TradeID?
    var media: [MediaReference]
    var parentMessageID: RoomMessageID?
    /// Web `room_messages.section_id` — owning channel.
    var channelID: RoomChannelID?
    var isPinned: Bool
    var createdAt: Date
    /// Room structured share type when encoded in `content` (`post`, `reel`, …).
    var shareType: String? = nil
    var reactions: [RoomMessageReaction] = []
}

// MARK: - Room management (owner tools)

nonisolated struct RoomMemberTag: Hashable, Codable, Sendable, Identifiable {
    var id: RoomMemberTagID
    var roomID: RoomID
    var name: String
    var colorKey: String
    var isPreset: Bool
}

nonisolated struct RoomMemberTagAssignment: Hashable, Codable, Sendable {
    var roomID: RoomID
    var profileID: ProfileID
    var tagID: RoomMemberTagID
}

nonisolated struct RoomManagedMember: Hashable, Sendable, Identifiable {
    var id: ProfileID { profile.id }
    var profile: Profile
    var role: RoomMemberRole
    var joinedAt: Date?
    var tags: [RoomMemberTag]
}

nonisolated struct RoomBanRecord: Hashable, Sendable, Identifiable {
    var id: String
    var roomID: RoomID
    var profileID: ProfileID
    var profile: Profile
    var bannedAt: Date
}

nonisolated struct RoomUpdateRequest: Sendable {
    var name: String?
    var description: String?
    var imageURL: String?
    var showsOnProfile: Bool?
}

nonisolated struct RoomChannelCreateRequest: Sendable {
    var name: String
    var allowMembersChat: Bool
}

nonisolated struct RoomChannelUpdateRequest: Sendable {
    var name: String?
    var allowMembersChat: Bool?
    var position: Int?
}

nonisolated enum RoomChannelValidation {
    static let maxCount = 5
    static let minCount = 1
    static let nameMaxLength = 64
}

/// Web `createUserRoom` parity — inserts `rooms`, default sections, and owner membership.
nonisolated struct RoomCreateRequest: Sendable {
    var name: String
    var description: String?
    var imageURL: String?
    /// Maps to `rooms.show_on_profile` (public discovery vs invite-link-only).
    var showsOnProfile: Bool

    enum Validation {
        static let nameMaxLength = 100
        static let descriptionMaxLength = 500
    }
}
