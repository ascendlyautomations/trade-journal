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

    /// Authors may delete own messages; room owners may delete any member message in their room.
    static func canDeleteMessage(
        viewerID: ProfileID?,
        senderProfileID: ProfileID,
        isRoomOwner: Bool
    ) -> Bool {
        guard viewerID != nil else { return false }
        if isOwnMessage(viewerID: viewerID, senderProfileID: senderProfileID) {
            return true
        }
        return isRoomOwner
    }

    /// Owner removing another member's message (confirmation required in UI).
    static func isOwnerDeletingAnotherMembersMessage(
        viewerID: ProfileID?,
        senderProfileID: ProfileID,
        isRoomOwner: Bool
    ) -> Bool {
        guard isRoomOwner else { return false }
        return !isOwnMessage(viewerID: viewerID, senderProfileID: senderProfileID)
    }

    /// Room owners may ban active members (not self, not the owner account).
    static func canBanMember(
        viewerID: ProfileID?,
        targetProfileID: ProfileID,
        roomOwnerProfileID: ProfileID?
    ) -> Bool {
        guard isRoomOwner(roomOwnerProfileID: roomOwnerProfileID, viewerID: viewerID) else {
            return false
        }
        guard let viewerID else { return false }
        return targetProfileID != viewerID && targetProfileID != roomOwnerProfileID
    }

    /// Manage member from message long-press — another member's sent, non-system message.
    static func canManageMessageMember(
        viewerID: ProfileID?,
        senderProfileID: ProfileID,
        roomOwnerProfileID: ProfileID?,
        messageKind: MessageKind,
        sendState: ConversationBubbleItem.SendState
    ) -> Bool {
        guard sendState == .sent, messageKind != .system else { return false }
        return canBanMember(
            viewerID: viewerID,
            targetProfileID: senderProfileID,
            roomOwnerProfileID: roomOwnerProfileID
        )
        && !isOwnMessage(viewerID: viewerID, senderProfileID: senderProfileID)
    }
}
