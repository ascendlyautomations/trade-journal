import Foundation

/// Presentation for official Trade Rooms — never fetched from Supabase `profiles`.
enum TradeRoomOfficialOwnerPresentation {
    static func systemOwnerProfile(roomID: RoomID) -> Profile {
        Profile(
            id: ProfileIDQueryPolicy.officialRoomSystemOwner(roomID: roomID),
            userID: UserID("tradetraxs"),
            username: "tradetraxs",
            displayName: "TradeTraxs",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: true,
            createdAt: .distantPast
        )
    }
}
