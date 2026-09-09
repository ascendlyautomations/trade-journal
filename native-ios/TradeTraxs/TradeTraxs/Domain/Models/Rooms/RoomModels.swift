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
    /// Hidden from public discovery when true (`rooms.is_private`).
    var isPrivate: Bool
    var category: TradeRoomCategory?
    var discoveryTags: [String]
    var joinPolicy: TradeRoomJoinPolicy
    var rules: String?
    var membersCanMessage: Bool
    var membersCanShareTrades: Bool
    var membersCanShareMedia: Bool
    var roomKind: TradeRoomKind
    var createdAt: Date

    init(
        id: RoomID,
        ownerProfileID: ProfileID,
        name: String,
        slug: String,
        description: String?,
        image: MediaReference?,
        memberCount: Int?,
        showsOnProfile: Bool,
        isPrivate: Bool = false,
        category: TradeRoomCategory? = nil,
        discoveryTags: [String] = [],
        joinPolicy: TradeRoomJoinPolicy = .open,
        rules: String? = nil,
        membersCanMessage: Bool = true,
        membersCanShareTrades: Bool = true,
        membersCanShareMedia: Bool = true,
        roomKind: TradeRoomKind = .community,
        createdAt: Date
    ) {
        self.id = id
        self.ownerProfileID = ownerProfileID
        self.name = name
        self.slug = slug
        self.description = description
        self.image = image
        self.memberCount = memberCount
        self.showsOnProfile = showsOnProfile
        self.isPrivate = isPrivate
        self.category = category
        self.discoveryTags = discoveryTags
        self.joinPolicy = joinPolicy
        self.rules = rules
        self.membersCanMessage = membersCanMessage
        self.membersCanShareTrades = membersCanShareTrades
        self.membersCanShareMedia = membersCanShareMedia
        self.roomKind = roomKind
        self.createdAt = createdAt
    }
}

nonisolated enum TradeRoomKind: String, Codable, Sendable, Hashable {
    case community
    case official

    static func parse(_ raw: String?) -> TradeRoomKind {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "official": return .official
        default: return .community
        }
    }
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
    var isPrivate: Bool?
    var category: TradeRoomCategory?
    var discoveryTags: [String]?
    var joinPolicy: TradeRoomJoinPolicy?
    var rules: String?
    var membersCanMessage: Bool?
    var membersCanShareTrades: Bool?
    var membersCanShareMedia: Bool?

    init(
        name: String? = nil,
        description: String? = nil,
        imageURL: String? = nil,
        showsOnProfile: Bool? = nil,
        isPrivate: Bool? = nil,
        category: TradeRoomCategory? = nil,
        discoveryTags: [String]? = nil,
        joinPolicy: TradeRoomJoinPolicy? = nil,
        rules: String? = nil,
        membersCanMessage: Bool? = nil,
        membersCanShareTrades: Bool? = nil,
        membersCanShareMedia: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.imageURL = imageURL
        self.showsOnProfile = showsOnProfile
        self.isPrivate = isPrivate
        self.category = category
        self.discoveryTags = discoveryTags
        self.joinPolicy = joinPolicy
        self.rules = rules
        self.membersCanMessage = membersCanMessage
        self.membersCanShareTrades = membersCanShareTrades
        self.membersCanShareMedia = membersCanShareMedia
    }

    init(configuration: TradeRoomConfiguration) {
        name = configuration.trimmedName
        description = configuration.trimmedDescription
        imageURL = configuration.imageURL
        showsOnProfile = configuration.showsOnProfile
        isPrivate = configuration.visibility == .private
        category = configuration.category
        discoveryTags = configuration.discoveryTags
        joinPolicy = configuration.effectiveJoinPolicy
        rules = configuration.trimmedRules
        membersCanMessage = configuration.membersCanMessage
        membersCanShareTrades = configuration.membersCanShareTrades
        membersCanShareMedia = configuration.membersCanShareMedia
    }
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

/// Authoritative create payload — `rpc_v1_create_trade_room`.
nonisolated struct RoomCreateRequest: Sendable {
    var configuration: TradeRoomConfiguration

    init(configuration: TradeRoomConfiguration) {
        self.configuration = configuration
    }

    enum Validation {
        static let nameMaxLength = TradeRoomConfigurationValidation.nameMaxLength
        static let descriptionMaxLength = TradeRoomConfigurationValidation.descriptionMaxLength
    }
}
