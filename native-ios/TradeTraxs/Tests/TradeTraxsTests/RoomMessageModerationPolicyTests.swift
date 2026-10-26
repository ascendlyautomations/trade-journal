import XCTest
@testable import TradeTraxs

final class RoomMessageModerationPolicyTests: XCTestCase {
    private let owner = ProfileID("owner-1")
    private let member = ProfileID("member-1")
    private let moderator = ProfileID("mod-1")
    private let otherOwner = ProfileID("owner-2")

    private func ownerManage() -> (Bool, Bool) { (true, true) }
    private func moderatorOnly() -> (Bool, Bool) { (false, true) }
    private func memberNone() -> (Bool, Bool) { (false, false) }

    func testMemberCanDeleteOwnMessageOnly() {
        XCTAssertTrue(
            RoomMessageModerationPolicy.canDeleteMessage(
                viewerID: member,
                senderProfileID: member,
                isRoomOwner: false
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canDeleteMessage(
                viewerID: member,
                senderProfileID: owner,
                isRoomOwner: false
            )
        )
    }

    func testRoomOwnerCanDeleteAnyMemberMessage() {
        XCTAssertTrue(
            RoomMessageModerationPolicy.canDeleteMessage(
                viewerID: owner,
                senderProfileID: member,
                isRoomOwner: true
            )
        )
    }

    func testModeratorCanDeleteMemberMessageNotOwner() {
        XCTAssertTrue(
            RoomMessageModerationPolicy.canDeleteMessage(
                viewerID: moderator,
                senderProfileID: member,
                isRoomOwner: false,
                isRoomModerator: true,
                roomOwnerProfileID: owner
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canDeleteMessage(
                viewerID: moderator,
                senderProfileID: owner,
                isRoomOwner: false,
                isRoomModerator: true,
                roomOwnerProfileID: owner
            )
        )
    }

    func testOwnerModerationDeleteRequiresConfirmationForOthers() {
        XCTAssertTrue(
            RoomMessageModerationPolicy.isOwnerDeletingAnotherMembersMessage(
                viewerID: owner,
                senderProfileID: member,
                isRoomOwner: true
            )
        )
    }

    func testOwnerCanBanMemberNotSelfOrOwner() {
        let manage = ownerManage()
        XCTAssertTrue(
            RoomMessageModerationPolicy.canBanMember(
                viewerID: owner,
                targetProfileID: member,
                roomOwnerProfileID: owner,
                canManageRoom: manage.0,
                canModerateRoom: manage.1
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canBanMember(
                viewerID: owner,
                targetProfileID: owner,
                roomOwnerProfileID: owner,
                canManageRoom: manage.0,
                canModerateRoom: manage.1
            )
        )
    }

    func testModeratorCannotBanAnotherModerator() {
        let mod = moderatorOnly()
        let modTag = RoomMemberTag(
            id: RoomMemberTagID("t-mod"),
            roomID: RoomID("room"),
            name: "Moderator",
            colorKey: "purple",
            isPreset: true
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canBanMember(
                viewerID: moderator,
                targetProfileID: member,
                roomOwnerProfileID: owner,
                canManageRoom: mod.0,
                canModerateRoom: mod.1,
                targetMemberTags: [modTag]
            )
        )
    }

    func testManageFromMessageRequiresModerationRights() {
        let manage = ownerManage()
        XCTAssertTrue(
            RoomMessageModerationPolicy.canManageMessageMember(
                viewerID: owner,
                senderProfileID: member,
                roomOwnerProfileID: owner,
                messageKind: .text,
                sendState: .sent,
                canManageRoom: manage.0,
                canModerateRoom: manage.1
            )
        )
        let none = memberNone()
        XCTAssertFalse(
            RoomMessageModerationPolicy.canManageMessageMember(
                viewerID: member,
                senderProfileID: owner,
                roomOwnerProfileID: owner,
                messageKind: .text,
                sendState: .sent,
                canManageRoom: none.0,
                canModerateRoom: none.1
            )
        )
    }
}
