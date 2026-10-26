import Foundation

/// Member-tag-based Trade Room moderation — mirrors ``can_moderate_trade_room`` on the backend.
enum TradeRoomModerationPermission {
    static let moderatorTagName = "Moderator"
    private static let elevatedTagNames: Set<String> = ["Moderator", "Admin"]

    static func hasModeratorTag(memberTags: [RoomMemberTag]) -> Bool {
        memberTags.contains { isModeratorTagName($0.name) }
    }

    static func hasElevatedTag(memberTags: [RoomMemberTag]) -> Bool {
        memberTags.contains { isElevatedTagName($0.name) }
    }

    static func canModerate(
        room: TradeRoom,
        viewerID: ProfileID?,
        viewerHasModeratorTag: Bool
    ) -> Bool {
        if TradeRoomManagementPermission.canManage(room: room, viewerID: viewerID) {
            return true
        }
        return viewerHasModeratorTag
    }

    static func canAssignTag(tag: RoomMemberTag, canManageRoom: Bool, canModerateRoom: Bool) -> Bool {
        guard canModerateRoom else { return false }
        if canManageRoom { return true }
        return !isElevatedTagName(tag.name)
    }

    static func canModerateMemberTarget(
        canManageRoom: Bool,
        canModerateRoom: Bool,
        viewerID: ProfileID?,
        roomOwnerProfileID: ProfileID,
        targetProfileID: ProfileID,
        targetMemberTags: [RoomMemberTag]
    ) -> Bool {
        guard canModerateRoom, let viewerID else { return false }
        if targetProfileID == viewerID || targetProfileID == roomOwnerProfileID { return false }
        if canManageRoom { return true }
        return !hasElevatedTag(memberTags: targetMemberTags)
    }

    static func viewerModeratorTags(
        viewerID: ProfileID,
        roomID: RoomID,
        tagStore: SessionRoomMemberTagsStore
    ) -> [RoomMemberTag] {
        let tags = tagStore.tags(for: roomID)
        let assigned = tagStore.assignments(for: roomID)
            .filter { $0.profileID == viewerID }
            .map(\.tagID)
        return tags.filter { assigned.contains($0.id) }
    }

    static func viewerHasModeratorTag(
        viewerID: ProfileID?,
        roomID: RoomID,
        tagStore: SessionRoomMemberTagsStore
    ) -> Bool {
        guard let viewerID else { return false }
        return hasModeratorTag(memberTags: viewerModeratorTags(
            viewerID: viewerID,
            roomID: roomID,
            tagStore: tagStore
        ))
    }

    private static func isModeratorTagName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(moderatorTagName) == .orderedSame
    }

    private static func isElevatedTagName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return elevatedTagNames.contains {
            trimmed.caseInsensitiveCompare($0) == .orderedSame
        }
    }
}
