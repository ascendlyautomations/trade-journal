import Foundation

/// Deterministic sample achievements for DEBUG development sessions / screenshots.
nonisolated enum ProfileAchievementFixtures {
    private static let sampleImageURL =
        "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"

    static func samples(owner profileID: ProfileID) -> [Achievement] {
        let now = Date()
        return [
            Achievement(
                id: AchievementID("dev-achievement-1"),
                ownerProfileID: profileID,
                kind: .propFirmPayout,
                title: "First Prop Payout",
                description: "Booked the first payout after a clean evaluation cycle.",
                tier: .gold,
                value: Money(amount: 2_500),
                valueText: nil,
                firm: "Alpha Futures",
                accountID: TradingAccountID("dev-account"),
                image: MediaReference(id: sampleImageURL, kind: .image, altText: "Payout certificate"),
                isPublic: true,
                isFeatured: true,
                sortOrder: 0,
                achievedAt: now.addingTimeInterval(-86_400 * 12)
            ),
            Achievement(
                id: AchievementID("dev-achievement-2"),
                ownerProfileID: profileID,
                kind: .passedEvaluation,
                title: "Passed Eval",
                description: "Hit profit target without violating daily drawdown.",
                tier: .silver,
                value: nil,
                valueText: "50K Eval",
                firm: "Alpha Futures",
                accountID: TradingAccountID("dev-account"),
                image: MediaReference(id: sampleImageURL, kind: .image, altText: "Eval pass"),
                isPublic: true,
                isFeatured: false,
                sortOrder: 1,
                achievedAt: now.addingTimeInterval(-86_400 * 40)
            ),
        ]
    }

    static func achievement(id: AchievementID) -> Achievement? {
        samples(owner: ProfileID("dev.fixture")).first { $0.id == id }
    }
}
