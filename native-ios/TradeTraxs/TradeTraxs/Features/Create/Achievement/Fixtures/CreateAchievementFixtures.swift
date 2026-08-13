import Foundation

enum CreateAchievementFixtures {
    static let viewerID = ProfileID("dev.createachievement.viewer")

    static func accounts(owner: ProfileID = viewerID) -> [TradingAccount] {
        [
            TradingAccount(
                id: TradingAccountID("dev.createachievement.personal"),
                ownerProfileID: owner,
                name: "Personal Live",
                category: .personal,
                mode: .live,
                size: Money(amount: 25_000),
                isActive: true,
                canAddTrades: true
            ),
            TradingAccount(
                id: TradingAccountID("dev.createachievement.prop"),
                ownerProfileID: owner,
                name: "Apex 50K",
                category: .propFirm,
                mode: .evaluation,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                propFirmRules: PropFirmAccountRules(maxDrawdown: 2_000, profitTarget: 3_000)
            ),
        ]
    }

    static func sampleAchievement(
        owner: ProfileID = viewerID,
        kind: AchievementKind = .milestone,
        title: String = "First green week"
    ) -> Achievement {
        Achievement(
            id: AchievementID("dev.createachievement.\(UUID().uuidString)"),
            ownerProfileID: owner,
            kind: kind,
            title: title,
            description: "Fixture achievement",
            tier: .bronze,
            value: nil,
            valueText: nil,
            firm: nil,
            accountID: nil,
            image: MediaReference(id: "dev/achievement.jpg", kind: .image, altText: nil),
            isPublic: true,
            isFeatured: false,
            sortOrder: 0,
            achievedAt: .now
        )
    }
}
