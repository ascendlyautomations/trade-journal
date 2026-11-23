import Foundation

@MainActor
enum TradeRoomMembershipSync {
    static func applyJoined(
        suggestion: ExploreRoomSuggestion,
        viewerID: ProfileID,
        inboxStore: MessagesInboxStore,
        confirmedMembership: RoomMembership? = nil
    ) {
        let tradeRoom = tradeRoom(from: suggestion)
        applyJoined(
            tradeRoom: tradeRoom,
            suggestion: suggestion,
            confirmedMembership: confirmedMembership,
            viewerID: viewerID,
            inboxStore: inboxStore
        )
    }

    static func applyJoined(
        tradeRoom: TradeRoom,
        viewerID: ProfileID,
        inboxStore: MessagesInboxStore,
        confirmedMembership: RoomMembership? = nil
    ) {
        applyJoined(
            tradeRoom: tradeRoom,
            suggestion: nil,
            confirmedMembership: confirmedMembership,
            viewerID: viewerID,
            inboxStore: inboxStore
        )
    }

    private static func applyJoined(
        tradeRoom: TradeRoom,
        suggestion: ExploreRoomSuggestion?,
        confirmedMembership: RoomMembership?,
        viewerID: ProfileID,
        inboxStore: MessagesInboxStore
    ) {
        TradeRoomMembershipStore.shared.setJoined(tradeRoom.id, joined: true)
        if let confirmedMembership {
            TradeRoomConfirmedMembershipCache.store(confirmedMembership, for: tradeRoom.id)
        }
        TradeRoomJoinActionCoordinator.shared.patchJoined(tradeRoom.id)

        if !inboxStore.rooms.contains(where: { $0.id == tradeRoom.id }) {
            inboxStore.replaceRooms(inboxStore.rooms + [tradeRoom])
        } else {
            inboxStore.applyRoomMetadata(tradeRoom)
        }

        SessionMemberRoomsStore.shared.upsertMemberRoom(tradeRoom, for: viewerID)

        GettingStartedRefreshCenter.noteJoinedOtherTradeRoom(
            from: suggestion ?? ExploreRoomSuggestion.fromMembership(
                room: tradeRoom,
                ownerName: nil,
                ownerUsername: nil,
                viewerID: viewerID,
                isOwner: tradeRoom.ownerProfileID == viewerID,
                isMember: true
            ),
            viewer: viewerID
        )
        SocialPersistedCacheCoordinator.invalidateRoomSnapshot(viewerID: viewerID, roomID: tradeRoom.id)
    }

    static func applyLeft(
        roomID: RoomID,
        viewerID: ProfileID,
        inboxStore: MessagesInboxStore
    ) {
        SocialPersistedCacheCoordinator.invalidateRoomSnapshot(viewerID: viewerID, roomID: roomID)
        TradeRoomMembershipStore.shared.setJoined(roomID, joined: false)
        TradeRoomConfirmedMembershipCache.clear(for: roomID)
        TradeRoomJoinActionCoordinator.shared.clearMutation(for: roomID)
        inboxStore.removeRoom(id: roomID)
        SessionMemberRoomsStore.shared.removeMemberRoom(roomID, for: viewerID)
    }

    static func patchExploreRoomSuggestion(_ room: ExploreRoomSuggestion) -> ExploreRoomSuggestion {
        var copy = room
        let storeJoined = TradeRoomMembershipStore.shared.isJoined(room.id)
        let joined = storeJoined
            || copy.viewerIsMember
            || copy.isJoined == true
        if joined {
            copy.isMember = true
            copy.isJoined = true
            if copy.viewerJoinRequestState == .pending {
                copy.viewerJoinRequestState = nil
            }
        } else if !storeJoined, !copy.viewerIsOwner {
            copy.isMember = false
            copy.isJoined = false
        }
        return copy
    }

    static func applyMembershipFlags(to rooms: [ExploreRoomSuggestion]) -> [ExploreRoomSuggestion] {
        rooms.map { patchExploreRoomSuggestion($0) }
    }

    static func tradeRoom(from suggestion: ExploreRoomSuggestion) -> TradeRoom {
        let ownerID = suggestion.ownerProfileID
            ?? ProfileIDQueryPolicy.officialRoomSystemOwner(roomID: suggestion.id)
        return TradeRoom(
            id: suggestion.id,
            ownerProfileID: ownerID,
            name: suggestion.name,
            slug: suggestion.slug,
            description: suggestion.description,
            image: suggestion.imageReference,
            memberCount: suggestion.memberCount,
            showsOnProfile: true,
            isPrivate: false,
            category: suggestion.category,
            discoveryTags: suggestion.discoveryTags,
            joinPolicy: suggestion.joinPolicy,
            roomKind: suggestion.roomKind,
            createdAt: .now
        )
    }
}