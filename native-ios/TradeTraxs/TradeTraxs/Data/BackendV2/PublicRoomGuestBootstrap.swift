import Foundation

nonisolated struct PublicRoomGuestBootstrapV1: Codable, Sendable {
    struct Meta: Codable, Sendable {
        var contract_version: String
        var guest: Bool?
        var server_time: String
    }

    struct RoomWire: Codable, Sendable {
        var id: String
        var name: String?
        var slug: String?
        var description: String?
        var image_url: String?
        var room_kind: String?
        var join_policy: String?
        var is_private: Bool?
    }

    struct DataWire: Codable, Sendable {
        var room: RoomWire
        var messages: [RoomDTO.Message]
        var next_cursor: String?
        var can_send_messages: Bool
    }

    var meta: Meta
    var data: DataWire

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct PublicRoomGuestRpcArguments: Encodable, Sendable {
    var p_room_id: String
    var p_section_id: String?
    var p_limit: Int
    var p_cursor: String?

    enum CodingKeys: String, CodingKey {
        case p_room_id
        case p_section_id
        case p_limit
        case p_cursor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_room_id, forKey: .p_room_id)
        if let p_section_id, !p_section_id.isEmpty {
            try container.encode(p_section_id, forKey: .p_section_id)
        } else {
            try container.encodeNil(forKey: .p_section_id)
        }
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
    }
}

nonisolated struct PublicRoomGuestRpcBootstrapRepository: Sendable {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(
        roomID: String,
        sectionID: String?,
        messageLimit: Int,
        cursor: String?
    ) async throws -> PublicRoomGuestBootstrapV1 {
        let args = PublicRoomGuestRpcArguments(
            p_room_id: roomID,
            p_section_id: sectionID,
            p_limit: messageLimit,
            p_cursor: cursor
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .publicRoomGuest,
            argumentsJSON: body,
            as: PublicRoomGuestBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.rooms.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

nonisolated enum PublicRoomGuestBootstrapApplier {
    struct Applied: Sendable {
        var room: TradeRoom
        var channels: [RoomChannel]
        var selectedChannelID: RoomChannelID
        var channelCache: RoomBootstrapApplier.ChannelThreadCache
    }

    @MainActor
    static func apply(
        _ bootstrap: PublicRoomGuestBootstrapV1,
        roomID: RoomID,
        viewerID: ProfileID
    ) throws -> Applied {
        try bootstrap.validateContractVersion()

        let roomWire = bootstrap.data.room
        let resolvedRoomID = RoomID(roomWire.id)
        let isPrivate = roomWire.is_private ?? false
        let joinPolicy = TradeRoomJoinPolicy(rawValue: roomWire.join_policy ?? "") ?? .open

        let room = TradeRoom(
            id: resolvedRoomID,
            ownerProfileID: ProfileID(""),
            name: roomWire.name ?? "Trade Room",
            slug: roomWire.slug ?? "",
            description: roomWire.description,
            image: roomWire.image_url.flatMap {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : MediaReference(id: trimmed, kind: .image, altText: nil)
            },
            memberCount: 0,
            showsOnProfile: !isPrivate,
            isPrivate: isPrivate,
            joinPolicy: joinPolicy,
            roomKind: TradeRoomKind.parse(roomWire.room_kind),
            createdAt: .now
        )

        let sectionIDs = Set(
            bootstrap.data.messages.compactMap { $0.section_id?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let channels: [RoomChannel]
        let selectedChannelID: RoomChannelID
        if sectionIDs.isEmpty {
            let fallback = RoomChannelID("\(resolvedRoomID.rawValue)-guest")
            channels = [
                RoomChannel(
                    id: fallback,
                    roomID: resolvedRoomID,
                    name: "General",
                    position: 0,
                    allowMembersChat: true
                ),
            ]
            selectedChannelID = fallback
        } else {
            channels = sectionIDs.enumerated().map { index, raw in
                RoomChannel(
                    id: RoomChannelID(raw),
                    roomID: resolvedRoomID,
                    name: "Channel",
                    position: index,
                    allowMembersChat: true
                )
            }
            selectedChannelID = channels[0].id
        }

        let roomMessages = bootstrap.data.messages.compactMap { mapMessage($0, roomID: resolvedRoomID) }
        let displayMessages = roomMessages
            .map(RoomMessageMapping.displayMessage)
            .sorted { $0.createdAt < $1.createdAt }
        let merged = ConversationMessageMerge.mergeMessages(
            existing: [],
            incoming: displayMessages,
            viewerID: viewerID
        )

        let cache = RoomBootstrapApplier.ChannelThreadCache(
            messages: merged,
            nextOlderCursor: bootstrap.data.next_cursor,
            hasMoreOlder: bootstrap.data.next_cursor != nil,
            scrollAnchorMessageID: merged.last?.id,
            isLoaded: true
        )

        return Applied(
            room: room,
            channels: channels,
            selectedChannelID: selectedChannelID,
            channelCache: cache
        )
    }

    private static func mapMessage(_ dto: RoomDTO.Message, roomID: RoomID) -> RoomMessage? {
        guard let id = dto.id else { return nil }
        let sender = dto.sender_id ?? dto.sender_profile_id ?? dto.user_id
        guard let sender else { return nil }
        let tradeID = dto.trade_id.flatMap { raw -> TradeID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : TradeID(trimmed)
        }
        let imageURL = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let media: [MediaReference] = {
            guard let imageURL, !imageURL.isEmpty else { return [] }
            return [MediaReference(id: imageURL, kind: .image, altText: nil)]
        }()
        return RoomMessage(
            id: RoomMessageID(id),
            roomID: roomID,
            senderProfileID: ProfileID(sender),
            body: dto.body ?? dto.content,
            attachedTradeID: tradeID,
            media: media,
            parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
            channelID: dto.section_id.map { RoomChannelID($0) },
            isPinned: dto.is_pinned ?? false,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            reactions: (dto.room_message_reactions ?? []).compactMap { reaction in
                guard let reactionID = reaction.id, let emoji = reaction.reaction, let user = reaction.user_id
                else { return nil }
                return RoomMessageReaction(
                    id: reactionID,
                    messageID: RoomMessageID(id),
                    userID: ProfileID(user),
                    reaction: emoji,
                    createdAt: ISO8601.date(from: reaction.created_at)
                )
            }
        )
    }
}

enum PublicRoomGuestBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
        case roomNotPublic
    }

    @MainActor
    static func load(
        roomID: RoomID,
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache
    ) async throws -> PublicRoomGuestBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.rooms) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.publicRoomGuest.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let roomFlightKey = BackendV2FlightKeys.room(
            viewerID: viewerID.rawValue,
            roomID: roomID.rawValue,
            sectionID: nil
        )
        let flightKey = "guest|\(roomFlightKey)"
        let bootstrap: PublicRoomGuestBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = PublicRoomGuestRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.load(
                    roomID: roomID.rawValue,
                    sectionID: nil,
                    messageLimit: 50,
                    cursor: nil
                )
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(PublicRoomGuestBootstrapV1.self, from: data)
            try bootstrap.validateContractVersion()
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(
                    rpcName: rpcName,
                    viewerID: viewerID.rawValue
                )
                throw LoaderError.rpcUnavailable
            }
            if (error as NSError).localizedDescription.contains("room_not_public") {
                throw LoaderError.roomNotPublic
            }
            throw error
        }

        return try PublicRoomGuestBootstrapApplier.apply(
            bootstrap,
            roomID: roomID,
            viewerID: viewerID
        )
    }
}
