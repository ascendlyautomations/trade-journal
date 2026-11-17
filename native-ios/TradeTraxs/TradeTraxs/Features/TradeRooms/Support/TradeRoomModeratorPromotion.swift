import Foundation

/// Assign or revoke the preset **Moderator** member tag (owner-only UI; same backend as tag APIs).
enum TradeRoomModeratorPromotion {
    static func moderatorTag(in roomTags: [RoomMemberTag]) -> RoomMemberTag? {
        roomTags.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(TradeRoomModerationPermission.moderatorTagName) == .orderedSame
        }
    }

    static func setModerator(
        promoted: Bool,
        roomID: RoomID,
        profileID: ProfileID,
        roomTags: [RoomMemberTag],
        tagStore: SessionRoomMemberTagsStore,
        management: RoomManagementRepository
    ) async throws {
        guard let modTag = moderatorTag(in: roomTags) else {
            throw TradeRoomModeratorPromotionError.moderatorTagMissing
        }
        let currentIDs = Set(tagStore.tags(for: profileID, roomID: roomID).map(\.id))
        if promoted {
            guard !currentIDs.contains(modTag.id) else { return }
            try await management.assignMemberTag(roomID: roomID, profileID: profileID, tagID: modTag.id)
            var updated = currentIDs
            updated.insert(modTag.id)
            tagStore.setMemberTagIDs(updated, profileID: profileID, roomID: roomID)
        } else {
            guard currentIDs.contains(modTag.id) else { return }
            try await management.removeMemberTagAssignment(
                roomID: roomID,
                profileID: profileID,
                tagID: modTag.id
            )
            var updated = currentIDs
            updated.remove(modTag.id)
            tagStore.setMemberTagIDs(updated, profileID: profileID, roomID: roomID)
        }
    }
}

enum TradeRoomModeratorPromotionError: LocalizedError {
    case moderatorTagMissing

    var errorDescription: String? {
        switch self {
        case .moderatorTagMissing:
            return "This room doesn't have a Moderator tag yet. Try again in a moment."
        }
    }
}