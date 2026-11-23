import Foundation

// MARK: - Authoritative room setup (create + owner edit)

nonisolated enum TradeRoomCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case futures
    case options
    case stocks
    case crypto
    case forex
    case propFirms = "prop_firms"
    case dayTrading = "day_trading"
    case swingTrading = "swing_trading"
    case general

    var displayName: String {
        switch self {
        case .futures: return "Futures"
        case .options: return "Options"
        case .stocks: return "Stocks"
        case .crypto: return "Crypto"
        case .forex: return "Forex"
        case .propFirms: return "Prop Firms"
        case .dayTrading: return "Day Trading"
        case .swingTrading: return "Swing Trading"
        case .general: return "General"
        }
    }

    /// Parses `rooms.category` from API / RPC (trimmed, lowercased snake_case).
    static func parseStored(_ raw: String?) -> TradeRoomCategory? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if let match = TradeRoomCategory(rawValue: trimmed) { return match }
        return TradeRoomCategory(rawValue: trimmed.lowercased())
    }

    /// Stored value, then official slug inference — never invents `.general` for NULL/legacy rows.
    static func effectiveForDiscovery(
        stored: TradeRoomCategory?,
        slug: String,
        roomKind: TradeRoomKind
    ) -> TradeRoomCategory? {
        if let stored { return stored }
        return inferredOfficialCategory(slug: slug, roomKind: roomKind)
    }

    /// Maps seeded official room slugs when `rooms.category` was never set.
    static func inferredOfficialCategory(slug: String, roomKind: TradeRoomKind) -> TradeRoomCategory? {
        guard roomKind == .official else { return nil }
        switch slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "futures-traders": return .futures
        case "options-traders": return .options
        case "stock-traders": return .stocks
        case "crypto-traders": return .crypto
        case "forex-traders": return .forex
        default: return nil
        }
    }
}

/// Stored on `rooms.is_private` — only set via ``TradeRoomConfiguration/persistedIsPrivate`` for create/update payloads.
nonisolated enum TradeRoomVisibility: String, Codable, Sendable, Hashable {
    case `public`
    case `private`
}

/// Owner-facing room access — replaces separate Private + Join Policy controls in create/edit UI.
nonisolated enum TradeRoomAccessMode: String, CaseIterable, Codable, Sendable, Hashable {
    case publicOpen
    case requestToJoin

    var displayName: String {
        switch self {
        case .publicOpen: return "Public"
        case .requestToJoin: return "Request to Join"
        }
    }

    var summary: String {
        switch self {
        case .publicOpen:
            return "Anyone can join instantly."
        case .requestToJoin:
            return "Users request membership and are approved before joining."
        }
    }
}

nonisolated enum TradeRoomJoinPolicy: String, Codable, Sendable, Hashable {
    case open
    case approval

    var displayName: String {
        switch self {
        case .open: return "Anyone can join"
        case .approval: return "Request to Join"
        }
    }
}

nonisolated struct TradeRoomDraftChannel: Hashable, Identifiable, Sendable, Codable {
    var id: UUID
    var name: String
    /// Per sub-room post permission — `room_sections.allow_members_chat`.
    var allowMembersChat: Bool

    init(id: UUID = UUID(), name: String, allowMembersChat: Bool = true) {
        self.id = id
        self.name = name
        self.allowMembersChat = allowMembersChat
    }
}

nonisolated enum TradeRoomConfigurationValidation {
    static let nameMaxLength = 100
    static let descriptionMaxLength = 500
    static let rulesMaxLength = 2000
    static let maxDiscoveryTags = 5
    static let maxChannels = RoomChannelValidation.maxCount
    static let channelNameMaxLength = RoomChannelValidation.nameMaxLength

    static let presetDiscoveryTags = [
        "Scalping",
        "Day Trading",
        "Swing Trading",
        "Futures",
        "Options",
        "Prop Firms",
        "Technical Analysis",
        "Trading Psychology",
        "Beginners",
    ]

    static func normalizedChannelName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasDuplicateChannelNames(_ channels: [TradeRoomDraftChannel]) -> Bool {
        var seen = Set<String>()
        for channel in channels {
            let key = normalizedChannelName(channel.name).lowercased()
            guard !key.isEmpty else { continue }
            if seen.contains(key) { return true }
            seen.insert(key)
        }
        return false
    }

    static func validate(_ configuration: TradeRoomConfiguration) -> String? {
        let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Room name is required." }
        if name.count > nameMaxLength {
            return "Room name must be \(nameMaxLength) characters or fewer."
        }

        let description = configuration.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if description.count > descriptionMaxLength {
            return "Description must be \(descriptionMaxLength) characters or fewer."
        }

        let rules = configuration.rules?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rules.count > rulesMaxLength {
            return "Room rules must be \(rulesMaxLength) characters or fewer."
        }

        if configuration.discoveryTags.count > maxDiscoveryTags {
            return "Choose up to \(maxDiscoveryTags) tags."
        }

        if configuration.channels.isEmpty {
            return "Add at least one sub-room."
        }
        if configuration.channels.count > maxChannels {
            return "You can have up to \(maxChannels) sub-rooms."
        }

        for channel in configuration.channels {
            let channelName = normalizedChannelName(channel.name)
            if channelName.isEmpty { return "Sub-room names cannot be blank." }
            if channelName.count > channelNameMaxLength {
                return "Sub-room names must be \(channelNameMaxLength) characters or fewer."
            }
        }

        if hasDuplicateChannelNames(configuration.channels) {
            return "Sub-room names must be unique."
        }

        return nil
    }
}

/// Single authoritative room setup payload — shared by create and owner edit flows.
nonisolated struct TradeRoomConfiguration: Hashable, Sendable {
    var name: String
    var description: String?
    var imageURL: String?
    var category: TradeRoomCategory?
    var discoveryTags: [String]
    var visibility: TradeRoomVisibility
    var showsOnProfile: Bool
    var joinPolicy: TradeRoomJoinPolicy
    var rules: String?
    var membersCanMessage: Bool
    var membersCanShareTrades: Bool
    var membersCanShareMedia: Bool
    var channels: [TradeRoomDraftChannel]
    /// Loaded from `rooms.is_private` on edit — kept when owner keeps Request to Join on a legacy private room.
    var preservesLegacyPrivate: Bool = false

    static func defaultDraft(username: String?) -> TradeRoomConfiguration {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultName = trimmed.isEmpty ? "" : "\(trimmed)'s Room"
        return TradeRoomConfiguration(
            name: defaultName,
            description: nil,
            imageURL: nil,
            category: .general,
            discoveryTags: [],
            visibility: .public,
            showsOnProfile: true,
            joinPolicy: .open,
            rules: nil,
            membersCanMessage: true,
            membersCanShareTrades: true,
            membersCanShareMedia: true,
            channels: [TradeRoomDraftChannel(name: "General")]
        )
    }

    init(
        name: String,
        description: String?,
        imageURL: String?,
        category: TradeRoomCategory?,
        discoveryTags: [String],
        visibility: TradeRoomVisibility,
        showsOnProfile: Bool,
        joinPolicy: TradeRoomJoinPolicy,
        rules: String?,
        membersCanMessage: Bool,
        membersCanShareTrades: Bool,
        membersCanShareMedia: Bool,
        channels: [TradeRoomDraftChannel],
        preservesLegacyPrivate: Bool = false
    ) {
        self.name = name
        self.description = description
        self.imageURL = imageURL
        self.category = category
        self.discoveryTags = discoveryTags
        self.visibility = visibility
        self.showsOnProfile = showsOnProfile
        self.joinPolicy = joinPolicy
        self.rules = rules
        self.membersCanMessage = membersCanMessage
        self.membersCanShareTrades = membersCanShareTrades
        self.membersCanShareMedia = membersCanShareMedia
        self.channels = channels
        self.preservesLegacyPrivate = preservesLegacyPrivate
    }

    init(room: TradeRoom, channels: [RoomChannel]) {
        name = room.name
        description = room.description
        imageURL = room.image?.id
        category = room.category
        discoveryTags = room.discoveryTags
        preservesLegacyPrivate = room.isPrivate
        visibility = room.isPrivate ? .private : .public
        showsOnProfile = room.showsOnProfile
        joinPolicy = room.isPrivate ? .open : room.joinPolicy
        rules = room.rules
        membersCanMessage = room.membersCanMessage
        membersCanShareTrades = room.membersCanShareTrades
        membersCanShareMedia = room.membersCanShareMedia
        self.channels = channels
            .sorted { $0.position < $1.position }
            .map {
                TradeRoomDraftChannel(
                    id: UUID(uuidString: $0.id.rawValue) ?? UUID(),
                    name: $0.name,
                    allowMembersChat: $0.allowMembersChat
                )
            }
        if self.channels.isEmpty {
            self.channels = [TradeRoomDraftChannel(name: "General")]
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String? {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedRules: String? {
        let trimmed = rules?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var accessMode: TradeRoomAccessMode {
        get {
            if preservesLegacyPrivate { return .requestToJoin }
            return joinPolicy == .approval ? .requestToJoin : .publicOpen
        }
        set {
            switch newValue {
            case .publicOpen:
                preservesLegacyPrivate = false
                visibility = .public
                joinPolicy = .open
            case .requestToJoin:
                joinPolicy = .approval
                if !preservesLegacyPrivate {
                    visibility = .public
                }
            }
        }
    }

    var persistedIsPrivate: Bool {
        preservesLegacyPrivate && accessMode == .requestToJoin
    }

    var effectiveJoinPolicy: TradeRoomJoinPolicy {
        if persistedIsPrivate { return .open }
        return joinPolicy
    }

    var hasUnsavedDraftChanges: Bool {
        !trimmedName.isEmpty
            || trimmedDescription != nil
            || imageURL != nil
            || category != .general
            || !discoveryTags.isEmpty
            || accessMode != .publicOpen
            || showsOnProfile == false
            || trimmedRules != nil
            || membersCanMessage == false
            || membersCanShareTrades == false
            || membersCanShareMedia == false
            || channels != [TradeRoomDraftChannel(name: "General")]
            || channels.contains { !$0.allowMembersChat }
    }
}
