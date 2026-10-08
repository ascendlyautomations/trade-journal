import XCTest
@testable import TradeTraxs

final class RoomMessageModerationPolicyTests: XCTestCase {
    private let owner = ProfileID("owner-1")
    private let member = ProfileID("member-1")
    private let otherOwner = ProfileID("owner-2")

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
        XCTAssertTrue(
            RoomMessageModerationPolicy.canDeleteMessage(
                viewerID: owner,
                senderProfileID: owner,
                isRoomOwner: true
            )
        )
    }

    func testNonOwnerCannotModerateOthersEvenWithWrongOwnerFlag() {
        XCTAssertFalse(
            RoomMessageModerationPolicy.canDeleteMessage(
                viewerID: member,
                senderProfileID: owner,
                isRoomOwner: false
            )
        )
    }

    func testOwnerModerationDeleteRequiresConfirmationForOthers() {
        XCTAssertFalse(
            RoomMessageModerationPolicy.isOwnerDeletingAnotherMembersMessage(
                viewerID: owner,
                senderProfileID: owner,
                isRoomOwner: true
            )
        )
        XCTAssertTrue(
            RoomMessageModerationPolicy.isOwnerDeletingAnotherMembersMessage(
                viewerID: owner,
                senderProfileID: member,
                isRoomOwner: true
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.isOwnerDeletingAnotherMembersMessage(
                viewerID: otherOwner,
                senderProfileID: member,
                isRoomOwner: false
            )
        )
    }

    func testIsRoomOwnerMatchesRoomOwnerProfileID() {
        XCTAssertTrue(
            RoomMessageModerationPolicy.isRoomOwner(
                roomOwnerProfileID: owner,
                viewerID: owner
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.isRoomOwner(
                roomOwnerProfileID: owner,
                viewerID: member
            )
        )
    }

    func testOwnerCanBanMemberNotSelfOrOwner() {
        XCTAssertTrue(
            RoomMessageModerationPolicy.canBanMember(
                viewerID: owner,
                targetProfileID: member,
                roomOwnerProfileID: owner
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canBanMember(
                viewerID: owner,
                targetProfileID: owner,
                roomOwnerProfileID: owner
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canBanMember(
                viewerID: member,
                targetProfileID: owner,
                roomOwnerProfileID: owner
            )
        )
    }

    func testManageFromMessageRequiresOwnerAndOtherSender() {
        XCTAssertTrue(
            RoomMessageModerationPolicy.canManageMessageMember(
                viewerID: owner,
                senderProfileID: member,
                roomOwnerProfileID: owner,
                messageKind: .text,
                sendState: .sent
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canManageMessageMember(
                viewerID: member,
                senderProfileID: owner,
                roomOwnerProfileID: owner,
                messageKind: .text,
                sendState: .sent
            )
        )
        XCTAssertFalse(
            RoomMessageModerationPolicy.canManageMessageMember(
                viewerID: owner,
                senderProfileID: member,
                roomOwnerProfileID: owner,
                messageKind: .system,
                sendState: .sent
            )
        )
    }
}
