import XCTest
@testable import TradeTraxs

final class AchievementDetailPresentationTests: XCTestCase {
    @MainActor
    func testMetadataRowsOmitsAchievedDate() {
        let achievement = sample(
            kind: .milestone,
            firm: "Topstep",
            valueText: "$50K"
        )
        let labels = AchievementDetailPresentation.metadataRows(for: achievement).map(\.label)
        XCTAssertFalse(labels.contains("Date achieved"))
    }

    func testTitleTrailingAccessoryForMilestone() {
        let achievement = sample(
            kind: .milestone,
            value: Money(amount: 50_000)
        )
        XCTAssertEqual(
            AchievementDetailPresentation.titleTrailingAccessory(for: achievement),
            TradeDisplay.pnlText(Money(amount: 50_000))
        )
    }

    func testTitleTrailingAccessoryNilForPayout() {
        let achievement = sample(
            kind: .propFirmPayout,
            value: Money(amount: 2_500)
        )
        XCTAssertNil(AchievementDetailPresentation.titleTrailingAccessory(for: achievement))
    }

    @MainActor
    func testContextCaptionJoinsTypeAndFirm() {
        let achievement = sample(kind: .propFirmPayout, firm: "Apex")
        XCTAssertEqual(
            AchievementDetailPresentation.contextCaption(for: achievement),
            "Prop Firm Payout · Apex"
        )
    }

    private func sample(
        kind: AchievementKind,
        firm: String? = nil,
        value: Money? = nil,
        valueText: String? = nil
    ) -> Achievement {
        Achievement(
            id: AchievementID("ach-1"),
            ownerProfileID: ProfileID("owner-1"),
            kind: kind,
            title: "Funded milestone",
            description: "Passed combine",
            tier: .gold,
            value: value,
            valueText: valueText,
            firm: firm,
            accountID: nil,
            image: nil,
            isPublic: true,
            isFeatured: false,
            sortOrder: 0,
            achievedAt: .now
        )
    }
}
