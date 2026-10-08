import XCTest
@testable import TradeTraxs

final class TradeTraxsOfficialAccountPolicyTests: XCTestCase {
    func testOfficialAccountRecognizedByStableProfileID() {
        XCTAssertTrue(
            TradeTraxsOfficialAccountPolicy.isOfficialTradeTraxsAccount(
                profileID: TradeTraxsOfficialAccountPolicy.profileID
            )
        )
    }

    func testUsernameAloneDoesNotGrantOfficialBadge() {
        let impostor = Profile(
            id: ProfileID("00000000-0000-4000-8000-000000000099"),
            userID: UserID("00000000-0000-4000-8000-000000000099"),
            username: "tradetraxs",
            displayName: "Fake TradeTraxs",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
        XCTAssertFalse(impostor.showsTradeTraxsIdentityBadge)
    }

    func testOfficialRoomSystemOwnerShowsBadge() {
        let systemOwner = ProfileIDQueryPolicy.officialRoomSystemOwner(
            roomID: RoomID("room-1")
        )
        XCTAssertTrue(TradeTraxsOfficialAccountPolicy.isOfficialTradeTraxsAccount(profileID: systemOwner))
    }

    func testCreatorBadgePreservedForNonOfficialProfiles() {
        let creator = Profile(
            id: ProfileID("00000000-0000-4000-8000-000000000088"),
            userID: UserID("00000000-0000-4000-8000-000000000088"),
            username: "creator",
            displayName: "Creator",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: true,
            createdAt: .now
        )
        XCTAssertTrue(creator.showsTradeTraxsIdentityBadge)
    }
}
