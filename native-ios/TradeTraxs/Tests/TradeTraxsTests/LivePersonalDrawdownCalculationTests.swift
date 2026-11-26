import XCTest
@testable import TradeTraxs

final class LivePersonalDrawdownCalculationTests: XCTestCase {
    private let profileID = ProfileID("11111111-1111-1111-1111-111111111111")
    private let accountID = TradingAccountID("22222222-2222-2222-2222-222222222222")

    private func liveAccount(
        size: Decimal,
        drawdownLimit: Decimal,
        drawdownType: LivePersonalDrawdownType,
        floorCap: Decimal? = nil
    ) -> TradingAccount {
        TradingAccount(
            id: accountID,
            ownerProfileID: profileID,
            name: "Live Broker",
            category: .broker,
            mode: .live,
            size: Money(amount: size),
            isActive: true,
            canAddTrades: true,
            livePersonalDrawdown: LivePersonalDrawdownStored(
                limitAmount: drawdownLimit,
                limitType: drawdownType,
                floorCap: floorCap
            )
        )
    }

    private func trade(pnl: Decimal, at: String) -> Trade {
        let stamp = ISO8601DateFormatter().date(from: at) ?? Date()
        return Trade(
            id: TradeID(UUID().uuidString),
            ownerProfileID: profileID,
            accountID: accountID,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryAt: stamp,
            exitAt: stamp,
            realizedPnL: Money(amount: pnl),
            visibility: .private,
            createdAt: stamp,
            updatedAt: stamp
        )
    }

    func testTrailingInitialFloorUsesStartingBalance() throws {
        let account = liveAccount(size: 50_000, drawdownLimit: 2_000, drawdownType: .trailing)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: [],
            ledgerEntries: [],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].equity, 50_000)
        XCTAssertEqual(samples[0].drawdownFloor, 48_000)
    }

    func testTrailingFloorRisesWithEquity() throws {
        let account = liveAccount(size: 50_000, drawdownLimit: 2_000, drawdownType: .trailing)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let trades = [
            trade(pnl: 500, at: "2024-06-01T14:00:00Z"),
            trade(pnl: 300, at: "2024-06-02T14:00:00Z"),
        ]
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: trades,
            ledgerEntries: [],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertEqual(samples.last?.equity, 50_800)
        XCTAssertEqual(samples.last?.drawdownFloor, 48_800)
    }

    func testTrailingFloorDoesNotRecedeWhenEquityFalls() throws {
        let account = liveAccount(size: 50_000, drawdownLimit: 2_000, drawdownType: .trailing)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let trades = [
            trade(pnl: 2_000, at: "2024-06-01T14:00:00Z"),
            trade(pnl: -1_500, at: "2024-06-02T14:00:00Z"),
        ]
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: trades,
            ledgerEntries: [],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertEqual(samples.last?.equity, 50_500)
        XCTAssertEqual(samples.last?.drawdownFloor, 50_000)
    }

    func testFixedFloorIgnoresPeakEquity() throws {
        let account = liveAccount(size: 25_000, drawdownLimit: 1_500, drawdownType: .fixed)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let trades = [trade(pnl: 5_000, at: "2024-06-01T14:00:00Z")]
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: trades,
            ledgerEntries: [],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertEqual(samples.last?.equity, 30_000)
        XCTAssertEqual(samples.last?.drawdownFloor, 23_500)
    }

    func testWithdrawalResetRebasesDrawdownBaseline() throws {
        let account = liveAccount(size: 40_000, drawdownLimit: 1_000, drawdownType: .trailing)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let trades = [trade(pnl: 2_000, at: "2024-06-01T14:00:00Z")]
        let payout = AccountPayoutEntry(
            id: AccountPayoutEntryID(UUID().uuidString),
            accountID: accountID,
            amount: Money(amount: 1_500),
            payoutDate: ISO8601DateFormatter().date(from: "2024-06-03T12:00:00Z") ?? Date(),
            note: "[[tt:dd=reset]]"
        )
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: trades,
            ledgerEntries: [payout],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertEqual(samples.last?.equity, 40_500)
        XCTAssertEqual(samples.last?.drawdownFloor, 39_500)
    }

    func testMissingStartingBalanceSkipsSeries() throws {
        var account = liveAccount(size: 0, drawdownLimit: 1_000, drawdownType: .trailing)
        account.size = nil
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: [trade(pnl: 100, at: "2024-06-01T14:00:00Z")],
            ledgerEntries: [],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertTrue(samples.isEmpty)
    }

    func testFixedDrawdownIgnoresFloorCap() throws {
        let account = liveAccount(size: 50_000, drawdownLimit: 2_000, drawdownType: .fixed, floorCap: 48_500)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let trades = [trade(pnl: 5_000, at: "2024-06-01T14:00:00Z")]
        let payout = AccountPayoutEntry(
            id: AccountPayoutEntryID(UUID().uuidString),
            accountID: accountID,
            amount: Money(amount: 1_500),
            payoutDate: ISO8601DateFormatter().date(from: "2024-06-03T12:00:00Z") ?? Date(),
            note: "[[tt:dd=reset]]"
        )
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: trades,
            ledgerEntries: [payout],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertEqual(samples[1].equity, 55_000)
        XCTAssertEqual(samples[1].drawdownFloor, 48_000)
        XCTAssertEqual(samples.last?.equity, 53_500)
        XCTAssertEqual(samples.last?.drawdownFloor, 51_500)
    }

    func testTrailingFloorCapStopsRisingAtConfiguredCap() throws {
        let account = liveAccount(size: 50_000, drawdownLimit: 2_000, drawdownType: .trailing, floorCap: 50_000)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        XCTAssertEqual(config.floorCap, 50_000)
        let trades = [
            trade(pnl: 3_000, at: "2024-06-01T10:00:00Z"),
            trade(pnl: 2_000, at: "2024-06-02T10:00:00Z"),
        ]
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: trades,
            ledgerEntries: [],
            period: .init(dateRange: .all, customInterval: nil)
        )
        XCTAssertEqual(samples[0].drawdownFloor, 48_000)
        XCTAssertEqual(samples.last?.equity, 55_000)
        XCTAssertEqual(samples.last?.drawdownFloor, 50_000)
    }

    func testTrailingFiveTradeSequenceThroughDashboardHeroPipeline() throws {
        let account = liveAccount(size: 50_000, drawdownLimit: 2_000, drawdownType: .trailing)
        let trades = [
            trade(pnl: 500, at: "2024-06-01T10:00:00Z"),
            trade(pnl: 500, at: "2024-06-02T10:00:00Z"),
            trade(pnl: -500, at: "2024-06-03T10:00:00Z"),
            trade(pnl: 1_500, at: "2024-06-04T10:00:00Z"),
            trade(pnl: -500, at: "2024-06-05T10:00:00Z"),
        ]
        let period = LivePersonalDrawdownEngine.PeriodContext(dateRange: .all, customInterval: nil)
        let heroInput = DashboardLivePersonalDrawdownHeroSeries.Input(
            account: account,
            lifetimeTrades: trades,
            ledgerEntries: [],
            period: period
        )
        let hero = try XCTUnwrap(DashboardLivePersonalDrawdownHeroSeries.resolve(heroInput))
        let chart = ProfileEquityCurvePresentation.chartPoints(from: hero)

        XCTAssertEqual(chart.map(\.equity), [50_000, 50_500, 51_000, 50_500, 52_000, 51_500])
        XCTAssertEqual(chart.map(\.drawdownFloor), [48_000, 48_500, 49_000, 49_000, 50_000, 50_000])

        let contaminated = DashboardEquityHeroPresentation.chartPoints(
            hero,
            propStartingBalance: 50_000
        )
        XCTAssertEqual(contaminated.map(\.equity), chart.map(\.equity))
        XCTAssertEqual(contaminated.map(\.drawdownFloor), chart.map(\.drawdownFloor))
    }

    func testScreenshotEarlyEquity64kFloorNotFromFutureHighWaterMark() throws {
        let account = liveAccount(size: 65_000, drawdownLimit: 2_000, drawdownType: .trailing)
        let config = try XCTUnwrap(LivePersonalDrawdownEngine.config(from: account))
        let trades = [
            trade(pnl: -1_000, at: "2024-01-15T14:00:00Z"),
            trade(pnl: 3_000, at: "2024-06-01T14:00:00Z"),
        ]
        let samples = LivePersonalDrawdownEngine.computeEquitySeries(
            account: account,
            config: config,
            lifetimeTrades: trades,
            ledgerEntries: [],
            period: .init(dateRange: .all, customInterval: nil)
        )
        let afterFirstLoss = samples[1]
        XCTAssertEqual(afterFirstLoss.equity, 64_000)
        XCTAssertEqual(afterFirstLoss.drawdownFloor, 63_000)
        XCTAssertLessThan(afterFirstLoss.drawdownFloor ?? 0, 66_000)

        let points = DashboardEquityHeroPresentation.chartPoints(
            LivePersonalDrawdownEngine.mapToEquityPoints(samples),
            propStartingBalance: 65_000
        )
        XCTAssertEqual(points[1].equity, 64_000)
        XCTAssertEqual(points[1].drawdownFloor, 63_000)
    }

    func testStartingBalancePolicyRequiresPersonalBrokerCreate() {
        let personal = TradingAccountDraft(
            name: "Live",
            sizeDigits: "",
            accountNumber: "",
            category: .personal,
            mode: .live,
            note: ""
        )
        XCTAssertTrue(TradingAccountStartingBalancePolicy.requiresStartingBalanceOnCreate(personal))
        XCTAssertNotNil(
            TradingAccountStartingBalancePolicy.validationMessage(for: personal.sizeDigits, context: .liveLedger)
        )

        let backtest = TradingAccountDraft(
            name: "Lab",
            sizeDigits: "",
            accountNumber: "",
            category: .backtest,
            mode: .backtest,
            note: ""
        )
        XCTAssertFalse(TradingAccountStartingBalancePolicy.requiresStartingBalanceOnCreate(backtest))
    }
}