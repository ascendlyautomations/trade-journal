import Foundation

/// Assign or revoke the preset **Moderator** member tag (owner-only UI; same backend as tag APIs).
enum TradeRoomModeratorPromotion {
    static func moderatorTag(in roomTags: [RoomMemberTag]) -> RoomMemberTag? {
        roomTags.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(TradeRoomModerationPermission.moderatorTagName) == .orderedSame
        }
    }

    static func projectedTagIDs(
        promoted: Bool,
        baseline: Set<RoomMemberTagID>,
        moderatorTagID: RoomMemberTagID
    ) -> Set<RoomMemberTagID> {
        var updated = baseline
        if promoted {
            updated.insert(moderatorTagID)
        } else {
            updated.remove(moderatorTagID)
        }
        return updated
    }

    static func setModerator(
        promoted: Bool,
        roomID: RoomID,
        profileID: ProfileID,
        roomTags: [RoomMemberTag],
        tagStore: SessionRoomMemberTagsStore,
        management: RoomManagementRepository,
        baselineMemberTagIDs: Set<RoomMemberTagID>? = nil
    ) async throws {
        guard let modTag = moderatorTag(in: roomTags) else {
            throw TradeRoomModeratorPromotionError.moderatorTagMissing
        }
        let baseline = baselineMemberTagIDs
            ?? Set(tagStore.tags(for: profileID, roomID: roomID).map(\.id))
        if promoted {
            guard !baseline.contains(modTag.id) else { return }
            try await management.assignMemberTag(roomID: roomID, profileID: profileID, tagID: modTag.id)
        } else {
            guard baseline.contains(modTag.id) else { return }
            try await management.removeMemberTagAssignment(
                roomID: roomID,
                profileID: profileID,
                tagID: modTag.id
            )
        }
        let updated = projectedTagIDs(
            promoted: promoted,
            baseline: baseline,
            moderatorTagID: modTag.id
        )
        tagStore.setMemberTagIDs(updated, profileID: profileID, roomID: roomID)
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