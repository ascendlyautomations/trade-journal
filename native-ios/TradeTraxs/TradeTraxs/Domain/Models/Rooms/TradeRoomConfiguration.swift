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
}

nonisolated enum TradeRoomVisibility: String, Codable, Sendable, Hashable {
    case `public`
    case `private`

    var displayName: String {
        switch self {
        case .public: return "Public"
        case .private: return "Private"
        }
    }

    var summary: String {
        switch self {
        case .public:
            return "Discoverable in Suggested, Popular, and Explore."
        case .private:
            return "Hidden from public discovery. Invite or link access only."
        }
    }
}

nonisolated enum TradeRoomJoinPolicy: String, Codable, Sendable, Hashable {
    case open
    case approval

    var displayName: String {
        switch self {
        case .open: return "Anyone can join"
        case .approval: return "Request to join"
        }
    }
}

nonisolated struct TradeRoomDraftChannel: Hashable, Identifiable, Sendable, Codable {
    var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
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

        if configuration.visibility == .private, configuration.joinPolicy == .approval {
            // Private rooms use invite/link; join policy only applies to public rooms.
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
        channels: [TradeRoomDraftChannel]
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
    }

    init(room: TradeRoom, channels: [RoomChannel]) {
        name = room.name
        description = room.description
        imageURL = room.image?.id
        category = room.category
        discoveryTags = room.discoveryTags
        visibility = room.isPrivate ? .private : .public
        showsOnProfile = room.showsOnProfile
        joinPolicy = room.joinPolicy
        rules = room.rules
        membersCanMessage = room.membersCanMessage
        membersCanShareTrades = room.membersCanShareTrades
        membersCanShareMedia = room.membersCanShareMedia
        self.channels = channels
            .sorted { $0.position < $1.position }
            .map { TradeRoomDraftChannel(id: UUID(uuidString: $0.id.rawValue) ?? UUID(), name: $0.name) }
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

    var effectiveJoinPolicy: TradeRoomJoinPolicy {
        visibility == .public ? joinPolicy : .open
    }

    var hasUnsavedDraftChanges: Bool {
        !trimmedName.isEmpty
            || trimmedDescription != nil
            || imageURL != nil
            || category != .general
            || !discoveryTags.isEmpty
            || visibility != .public
            || showsOnProfile == false
            || joinPolicy != .open
            || trimmedRules != nil
            || membersCanMessage == false
            || membersCanShareTrades == false
            || membersCanShareMedia == false
            || channels != [TradeRoomDraftChannel(name: "General")]
    }
}
