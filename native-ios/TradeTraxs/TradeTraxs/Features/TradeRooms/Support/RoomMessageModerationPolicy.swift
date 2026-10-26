import Foundation

/// Trade Room message moderation — aligned with web ``lib/roomModeration.ts``.
enum RoomMessageModerationPolicy {
    static func isRoomOwner(
        roomOwnerProfileID: ProfileID?,
        viewerID: ProfileID?
    ) -> Bool {
        guard let roomOwnerProfileID, let viewerID else { return false }
        return roomOwnerProfileID == viewerID
    }

    static func isOwnMessage(
        viewerID: ProfileID?,
        senderProfileID: ProfileID
    ) -> Bool {
        guard let viewerID else { return false }
        return senderProfileID == viewerID
    }

    /// Authors may delete own messages; owners/moderators may delete member messages (not the owner's).
    static func canDeleteMessage(
        viewerID: ProfileID?,
        senderProfileID: ProfileID,
        isRoomOwner: Bool,
        isRoomModerator: Bool = false,
        roomOwnerProfileID: ProfileID? = nil
    ) -> Bool {
        guard viewerID != nil else { return false }
        if isOwnMessage(viewerID: viewerID, senderProfileID: senderProfileID) {
            return true
        }
        let canModerate = isRoomOwner || isRoomModerator
        guard canModerate else { return false }
        if let roomOwnerProfileID,
           senderProfileID == roomOwnerProfileID,
           !isRoomOwner {
            return false
        }
        return true
    }

    /// Staff removing another member's message (confirmation required in UI).
    static func isStaffDeletingAnotherMembersMessage(
        viewerID: ProfileID?,
        senderProfileID: ProfileID,
        isRoomOwner: Bool,
        isRoomModerator: Bool
    ) -> Bool {
        guard isRoomOwner || isRoomModerator else { return false }
        return !isOwnMessage(viewerID: viewerID, senderProfileID: senderProfileID)
    }

    /// Owner removing another member's message (confirmation required in UI).
    static func isOwnerDeletingAnotherMembersMessage(
        viewerID: ProfileID?,
        senderProfileID: ProfileID,
        isRoomOwner: Bool
    ) -> Bool {
        isStaffDeletingAnotherMembersMessage(
            viewerID: viewerID,
            senderProfileID: senderProfileID,
            isRoomOwner: isRoomOwner,
            isRoomModerator: false
        )
    }

    /// Owners/moderators may ban or remove eligible members.
    static func canBanMember(
        viewerID: ProfileID?,
        targetProfileID: ProfileID,
        roomOwnerProfileID: ProfileID?,
        canManageRoom: Bool,
        canModerateRoom: Bool,
        targetMemberTags: [RoomMemberTag] = []
    ) -> Bool {
        guard let roomOwnerProfileID, let viewerID else { return false }
        return TradeRoomModerationPermission.canModerateMemberTarget(
            canManageRoom: canManageRoom,
            canModerateRoom: canModerateRoom,
            viewerID: viewerID,
            roomOwnerProfileID: roomOwnerProfileID,
            targetProfileID: targetProfileID,
            targetMemberTags: targetMemberTags
        )
    }

    /// Manage member from message long-press — another member's sent, non-system message.
    static func canManageMessageMember(
        viewerID: ProfileID?,
        senderProfileID: ProfileID,
        roomOwnerProfileID: ProfileID?,
        messageKind: MessageKind,
        sendState: ConversationBubbleItem.SendState,
        canManageRoom: Bool,
        canModerateRoom: Bool,
        targetMemberTags: [RoomMemberTag] = []
    ) -> Bool {
        guard sendState == .sent, messageKind != .system else { return false }
        return canBanMember(
            viewerID: viewerID,
            targetProfileID: senderProfileID,
            roomOwnerProfileID: roomOwnerProfileID,
            canManageRoom: canManageRoom,
            canModerateRoom: canModerateRoom,
            targetMemberTags: targetMemberTags
        )
        && !isOwnMessage(viewerID: viewerID, senderProfileID: senderProfileID)
    }
}
