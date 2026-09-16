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
    /// Active members from discovery RPC or batch hydration. Nil until loaded.
    var memberCount: Int?
    var imageURL: String?
    var ownerProfileID: ProfileID?
    var ownerUsername: String?
    var ownerDisplayName: String?
    var ownerAvatarURL: String?
    /// Active members the viewer follows — used for Suggested ranking badge.
    var followedMemberCount: Int?
    /// Authoritative backend classification — never inferred from room name in UI.
    var roomKind: TradeRoomKind
    /// Discovery/search labels from backend (`rooms.discovery_tags`).
    var discoveryTags: [String]
    /// Search RPC may include membership; discovery excludes joined rooms server-side.
    var isJoined: Bool?
    /// Authoritative viewer relationship from Trade Rooms RPC (`rooms.owner_user_id = auth.uid()`).
    var isOwner: Bool?
    /// Authoritative active membership (`room_members.left_at IS NULL`).
    var isMember: Bool?
    /// `rooms.join_policy` — open vs approval (request to join).
    var joinPolicy: TradeRoomJoinPolicy
    /// Viewer row in `room_join_requests` when present.
    var viewerJoinRequestState: TradeRoomJoinRequestState?

    init(
        id: RoomID,
        name: String,
        slug: String,
        description: String? = nil,
        memberCount: Int? = nil,
        imageURL: String? = nil,
        ownerProfileID: ProfileID? = nil,
        ownerUsername: String? = nil,
        ownerDisplayName: String? = nil,
        ownerAvatarURL: String? = nil,
        followedMemberCount: Int? = nil,
        roomKind: TradeRoomKind = .community,
        discoveryTags: [String] = [],
        isJoined: Bool? = nil,
        isOwner: Bool? = nil,
        isMember: Bool? = nil,
        joinPolicy: TradeRoomJoinPolicy = .open,
        viewerJoinRequestState: TradeRoomJoinRequestState? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.memberCount = memberCount
        self.imageURL = imageURL
        self.ownerProfileID = ownerProfileID
        self.ownerUsername = ownerUsername
        self.ownerDisplayName = ownerDisplayName
        self.ownerAvatarURL = ownerAvatarURL
        self.followedMemberCount = followedMemberCount
        self.roomKind = roomKind
        self.discoveryTags = discoveryTags
        self.isJoined = isJoined
        self.isOwner = isOwner
        self.isMember = isMember
        self.joinPolicy = joinPolicy
        self.viewerJoinRequestState = viewerJoinRequestState
    }

    /// Prefer authoritative RPC flags; fall back to legacy joined marker only when RPC omitted fields.
    var viewerIsOwner: Bool {
        isOwner == true
    }

    var viewerIsMember: Bool {
        isMember == true || isJoined == true
    }

    var requiresJoinRequest: Bool {
        joinPolicy == .approval
    }

    var isOfficial: Bool { roomKind == .official }

    var tagsLine: String? {
        let trimmed = discoveryTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return nil }
        return trimmed.prefix(3).joined(separator: " · ")
    }

    /// Web `resolveRoomAvatarUrl` parity — room image first, storage path or HTTPS preserved.
    var imageReference: MediaReference? {
        guard let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return MediaReference(id: raw, kind: .image, altText: nil)
    }

    var ownerDisplayLabel: String? {
        let username = ownerUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let username, !username.isEmpty { return "@\(username)" }
        let name = ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return nil
    }

    /// Patches discovery/search card fields from authoritative room metadata.
    mutating func applyMetadata(from room: TradeRoom) {
        name = room.name
        slug = room.slug
        description = room.description
        if let count = room.memberCount {
            memberCount = count
        }
        imageURL = room.image?.id
        discoveryTags = room.discoveryTags
        joinPolicy = room.joinPolicy
        roomKind = room.roomKind
    }

    /// Maps authoritative member-room state into the shared discovery row model.
    static func fromMembership(
        room: TradeRoom,
        ownerName: String?,
        ownerUsername: String?,
        viewerID: ProfileID?,
        isOwner: Bool? = nil,
        isMember: Bool? = nil
    ) -> ExploreRoomSuggestion {
        let resolvedOwner: Bool?
        if let isOwner {
            resolvedOwner = isOwner
        } else if let viewerID {
            resolvedOwner = room.ownerProfileID == viewerID
        } else {
            resolvedOwner = nil
        }
        return ExploreRoomSuggestion(
            id: room.id,
            name: room.name,
            slug: room.slug,
            description: room.description,
            memberCount: room.memberCount,
            imageURL: room.image?.id,
            ownerProfileID: room.ownerProfileID,
            ownerUsername: ownerUsername,
            ownerDisplayName: ownerName,
            ownerAvatarURL: nil,
            followedMemberCount: nil,
            roomKind: room.roomKind,
            discoveryTags: room.discoveryTags,
            isJoined: true,
            isOwner: resolvedOwner,
            isMember: isMember ?? true,
            joinPolicy: room.joinPolicy,
            viewerJoinRequestState: nil
        )
    }
}

/// Single-call Trade Rooms home bootstrap — Your Rooms + Suggested + Popular.
nonisolated struct TradeRoomsHomeBootstrap: Hashable, Sendable {
    var viewerID: ProfileID?
    var scope: TradeRoomDiscoveryScope
    var yourRooms: [ExploreRoomSuggestion]
    var suggested: [ExploreRoomSuggestion]
    var popular: [ExploreRoomSuggestion]
}

/// All / Official / Community filter for Trade Rooms discovery.
nonisolated enum TradeRoomDiscoveryScope: String, CaseIterable, Hashable, Sendable, Identifiable {
    case all
    case official
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .official: return "Official"
        case .community: return "Community"
        }
    }

    var rpcValue: String { rawValue }
}

/// Trade Rooms home discovery modes — all backed by `rpc_v1_trade_rooms_home_bootstrap` / discovery RPC.
nonisolated enum TradeRoomDiscoveryMode: String, CaseIterable, Hashable, Sendable, Identifiable {
    case yourRooms = "your_rooms"
    case suggested
    case popular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yourRooms: return "Your Rooms"
        case .suggested: return "Suggested"
        case .popular: return "Popular"
        }
    }

    var usesDiscoveryRPC: Bool { true }

    var rpcValue: String { rawValue }

    var emptyMessage: String {
        switch self {
        case .yourRooms: return "You haven't joined any rooms yet."
        case .suggested: return "No suggested rooms yet."
        case .popular: return "No public Trade Rooms to discover yet."
        }
    }
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
