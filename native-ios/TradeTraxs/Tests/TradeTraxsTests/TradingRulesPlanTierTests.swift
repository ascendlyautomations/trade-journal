import XCTest
@testable import TradeTraxs

final class TradingRulesPlanTierTests: XCTestCase {
    func testFreeTierIncludesExactlyFiveRuleFamilies() {
        XCTAssertEqual(TradingRulesPlanTier.freeRuleIDs.count, 5)
        XCTAssertTrue(TradingRulesPlanTier.freeRuleIDs.contains(.preferredSession))
        XCTAssertTrue(TradingRulesPlanTier.freeRuleIDs.contains(.allowedTradingDay))
        XCTAssertTrue(TradingRulesPlanTier.freeRuleIDs.contains(.maxTradesPerDay))
        XCTAssertTrue(TradingRulesPlanTier.freeRuleIDs.contains(.maxContracts))
        XCTAssertTrue(TradingRulesPlanTier.freeRuleIDs.contains(.primaryInstrument))
        XCTAssertFalse(TradingRulesPlanTier.freeRuleIDs.contains(.minPlannedRr))
        XCTAssertFalse(TradingRulesPlanTier.freeRuleIDs.contains(.maxRiskPerTrade))
    }

    func testPremiumTierIncludesMovedRrAndRiskRules() {
        XCTAssertTrue(TradingRulesPlanTier.premiumRuleIDs.contains(.minPlannedRr))
        XCTAssertTrue(TradingRulesPlanTier.premiumRuleIDs.contains(.maxRiskPerTrade))
    }

    func testFreeConfiguredRulesIgnorePremiumOnlyFields() {
        var global = TradingPreferenceGlobal.empty(userID: ProfileID("tier-test"))
        global.minAcceptableRr = 2
        global.maxRiskPerTrade = 400
        let context = PreferenceRuleContext(revisions: [], global: global, overrides: [])
        XCTAssertFalse(TradingRulesPlanTier.hasConfiguredFreeTierRules(context: context))

        global.minAcceptableRr = nil
        global.maxRiskPerTrade = nil
        global.maxTradesPerDay = 5
        let configured = PreferenceRuleContext(revisions: [], global: global, overrides: [])
        XCTAssertTrue(TradingRulesPlanTier.hasConfiguredFreeTierRules(context: configured))
    }

    func testComplianceFilterForFreeTier() {
        let filter = TradingRulesPlanTier.complianceRuleFilter(isFreeTier: true)
        XCTAssertEqual(filter, TradingRulesPlanTier.freeRuleIDs)
        XCTAssertNil(TradingRulesPlanTier.complianceRuleFilter(isFreeTier: false))
    }
}