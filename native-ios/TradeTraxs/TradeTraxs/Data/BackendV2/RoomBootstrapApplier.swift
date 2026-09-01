import Foundation

nonisolated enum RoomBootstrapApplier {
    struct Applied: Sendable {
        var room: TradeRoom
        var membership: RoomMembership
        var channels: [RoomChannel]
        var selectedChannelID: RoomChannelID
        var channelCache: ChannelThreadCache
        var markReadApplied: Bool
    }

    struct ChannelThreadCache: Sendable {
        var messages: [Message]
        var nextOlderCursor: String?
        var hasMoreOlder: Bool
        var scrollAnchorMessageID: MessageID?
        var isLoaded: Bool
    }

    @MainActor
    static func apply(
        _ bootstrap: RoomsBootstrapV1,
        roomID: RoomID,
        viewerID: ProfileID,
        detailCache: DetailPresentationCache
    ) throws -> Applied {
        try bootstrap.validateContractVersion()

        let roomWire = bootstrap.data.room
        let resolvedRoomID = RoomID(roomWire.id)
        let ownerID = ProfileID(roomWire.owner_user_id ?? "")
        let memberCount = bootstrap.data.member_stats?.total_members ?? 0

        let room = TradeRoom(
            id: resolvedRoomID,
            ownerProfileID: ownerID,
            name: roomWire.name ?? "Trade Room",
            slug: roomWire.slug ?? "",
            description: roomWire.description,
            image: roomWire.image_url.flatMap {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : MediaReference(id: trimmed, kind: .image, altText: nil)
            },
            memberCount: memberCount,
            showsOnProfile: roomWire.show_on_profile ?? true,
            createdAt: ISO8601.date(from: roomWire.created_at ?? "") ?? .now
        )

        let membershipWire = bootstrap.data.membership
        let membership = RoomMembership(
            roomID: resolvedRoomID,
            profileID: viewerID,
            role: membershipWire.is_owner ? .owner : .member,
            joinedAt: .now,
            notificationsEnabled: membershipWire.notification_enabled
        )

        let channels = bootstrap.data.sections.compactMap { section -> RoomChannel? in
            let name = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return RoomChannel(
                id: RoomChannelID(section.id),
                roomID: RoomID(section.room_id),
                name: name,
                position: section.position,
                allowMembersChat: section.allow_members_chat
            )
        }

        guard let selectedChannelID = bootstrap.data.active_section_id
            .flatMap({ RoomChannelID($0) })
            ?? channels.first?.id
        else {
            throw BackendV2RPCError.decode("room bootstrap missing active section")
        }

        let pinned = bootstrap.data.pinned_messages.compactMap { mapMessage($0) }
        let main = bootstrap.data.messages.compactMap { mapMessage($0) }
        let roomMessages = pinned + main
        let displayMessages = roomMessages
            .map(RoomMessageMapping.displayMessage)
            .sorted { $0.createdAt < $1.createdAt }
        let merged = ConversationMessageMerge.mergeMessages(
            existing: [],
            incoming: displayMessages,
            viewerID: viewerID
        )

        let cache = ChannelThreadCache(
            messages: merged,
            nextOlderCursor: bootstrap.data.next_message_cursor,
            hasMoreOlder: bootstrap.data.has_more_messages,
            scrollAnchorMessageID: merged.last?.id,
            isLoaded: true
        )

        if ownerID.rawValue.isEmpty == false, detailCache.profile(id: ownerID) == nil {
            // Owner card hydrates lazily via SessionProfileStore when absent.
            _ = ownerID
        }

        return Applied(
            room: room,
            membership: membership,
            channels: channels,
            selectedChannelID: selectedChannelID,
            channelCache: cache,
            markReadApplied: bootstrap.data.mark_read.applied
        )
    }

    private static func mapMessage(_ dto: RoomDTO.Message) -> RoomMessage? {
        guard let id = dto.id, let roomID = dto.room_id else { return nil }
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
            roomID: RoomID(roomID),
            senderProfileID: ProfileID(sender),
            body: dto.body ?? dto.content,
            attachedTradeID: tradeID,
            media: media,
            parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
            channelID: dto.section_id.map { RoomChannelID($0) },
            isPinned: dto.is_pinned ?? false,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            reactions: (dto.room_message_reactions ?? []).compactMap { mapReaction($0, fallbackMessageID: RoomMessageID(id)) }
        )
    }

    private static func mapReaction(
        _ dto: RoomDTO.ReactionRow,
        fallbackMessageID: RoomMessageID
    ) -> RoomMessageReaction? {
        guard let id = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let reaction = dto.reaction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reaction.isEmpty,
              RoomMessageReactionSemantics.supportedEmojis.contains(reaction)
        else { return nil }
        let messageRaw = dto.message_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageID = messageRaw.flatMap { raw -> RoomMessageID? in
            raw.isEmpty ? nil : RoomMessageID(raw)
        } ?? fallbackMessageID
        guard let userRaw = dto.user_id?.trimmingCharacters(in: .whitespacesAndNewlines), !userRaw.isEmpty
        else { return nil }
        return RoomMessageReaction(
            id: id,
            messageID: messageID,
            userID: ProfileID(userRaw),
            reaction: reaction,
            createdAt: ISO8601.date(from: dto.created_at)
        )
    }
}
