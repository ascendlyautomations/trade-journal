import Foundation

enum AddTradeFixtures {
    static let viewerID = ProfileID("dev.addtrade.viewer")

    static func accounts(owner: ProfileID = viewerID) -> [TradingAccount] {
        [
            TradingAccount(
                id: TradingAccountID("dev.addtrade.personal"),
                ownerProfileID: owner,
                name: "Personal Live",
                category: .personal,
                mode: .live,
                size: Money(amount: 25_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "10001"
            ),
            TradingAccount(
                id: TradingAccountID("dev.addtrade.prop"),
                ownerProfileID: owner,
                name: "Alpha 50K",
                category: .propFirm,
                mode: .evaluation,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "500123",
                propFirmRules: PropFirmAccountRules(maxDrawdown: 2_000, profitTarget: 3_000)
            ),
            TradingAccount(
                id: TradingAccountID("dev.addtrade.readonly"),
                ownerProfileID: owner,
                name: "Archived",
                category: .personal,
                mode: .live,
                size: Money(amount: 10_000),
                isActive: true,
                canAddTrades: false,
                accountNumber: "99999"
            ),
        ]
    }

    static var recentSymbols: [String] { ["MNQ", "NQ", "MES", "ES", "CL"] }

    static func unattachedReels(owner: ProfileID = viewerID) -> [Reel] {
        [
            Reel(
                id: ReelID("dev.addtrade.reel.1"),
                authorProfileID: owner,
                video: MediaReference(id: "dev/reel1.mp4", kind: .video, altText: nil),
                thumbnail: MediaReference(id: "dev/reel1.jpg", kind: .image, altText: nil),
                caption: "MNQ Breakdown",
                visibility: .public,
                linkedTradeID: nil,
                durationSeconds: 42,
                createdAt: Date().addingTimeInterval(-86_400)
            ),
            Reel(
                id: ReelID("dev.addtrade.reel.2"),
                authorProfileID: owner,
                video: MediaReference(id: "dev/reel2.mp4", kind: .video, altText: nil),
                thumbnail: nil,
                caption: "ORB scalp notes",
                visibility: .public,
                linkedTradeID: nil,
                durationSeconds: 28,
                createdAt: Date().addingTimeInterval(-172_800)
            ),
        ]
    }
}
