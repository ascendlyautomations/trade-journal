import Foundation

nonisolated enum RoomBootstrapApplier {
    struct Applied: Sendable {
        var room: TradeRoom
        var membership: RoomMembership?
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
        let ownerID: ProfileID = {
            let raw = roomWire.owner_user_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                return ProfileIDQueryPolicy.officialRoomSystemOwner(roomID: resolvedRoomID)
            }
            return ProfileID(raw)
        }()
        let memberCount = RoomMemberCountAuthority.resolve(
            memberStats: bootstrap.data.member_stats,
            activeMemberCount: bootstrap.data.active_member_count
        )

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
            isPrivate: roomWire.is_private ?? false,
            joinPolicy: TradeRoomJoinPolicy(rawValue: roomWire.join_policy ?? "") ?? .open,
            createdAt: ISO8601.date(from: roomWire.created_at ?? "") ?? .now
        )

        let membershipWire = bootstrap.data.membership
        let membership: RoomMembership? = membershipWire.is_member
            ? RoomMembership(
                roomID: resolvedRoomID,
                profileID: viewerID,
                role: membershipWire.is_owner ? .owner : .member,
                joinedAt: .now,
                notificationsEnabled: membershipWire.notification_enabled
            )
            : nil

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

        let pinned = bootstrap.data.pinned_messages.compactMap {
            RoomMessageDTOMapper.mapMessage($0, fallbackRoomID: resolvedRoomID)
        }
        let main = bootstrap.data.messages.compactMap {
            RoomMessageDTOMapper.mapMessage($0, fallbackRoomID: resolvedRoomID)
        }
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

}
