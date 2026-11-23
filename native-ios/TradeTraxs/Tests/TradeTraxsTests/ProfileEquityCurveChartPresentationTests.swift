import XCTest
@testable import TradeTraxs

final class ProfileEquityCurveChartPresentationTests: XCTestCase {
    func testDrawdownFloorUsesSameBalanceScaleAsEquity() {
        let input = [
            ProfileStatisticsMetrics.EquityPoint(index: 0, equity: 64_000, date: nil, drawdownFloor: 63_000),
            ProfileStatisticsMetrics.EquityPoint(index: 1, equity: 68_000, date: nil, drawdownFloor: 66_000),
        ]
        let alignment = ProfileEquityCurveChartModel.balanceSeriesAlignment(from: input)

        XCTAssertEqual(alignment[0].equityY, 64_000)
        XCTAssertEqual(alignment[0].floorY, 63_000)
        XCTAssertEqual(alignment[1].equityY, 68_000)
        XCTAssertEqual(alignment[1].floorY, 66_000)

        let domain = ProfileEquityCurveChartModel.yDomain(
            for: ProfileEquityCurveChartModel.renderPoints(from: input)
        )
        XCTAssertLessThan(domain.lowerBound, 63_000)
        XCTAssertGreaterThan(domain.upperBound, 68_000)
    }

    func testHeroPipelineValuesReachChartUnmodified() throws {
        let account = TradingAccount(
            id: TradingAccountID("22222222-2222-2222-2222-222222222222"),
            ownerProfileID: ProfileID("11111111-1111-1111-1111-111111111111"),
            name: "Live",
            category: .broker,
            mode: .live,
            size: Money(amount: 50_000),
            isActive: true,
            canAddTrades: true,
            livePersonalDrawdown: LivePersonalDrawdownStored(
                limitAmount: 2_000,
                limitType: .trailing
            )
        )
        let trades = [
            trade(pnl: 500, at: "2024-06-01T10:00:00Z"),
            trade(pnl: -1_000, at: "2024-06-02T10:00:00Z"),
        ]
        let hero = try XCTUnwrap(
            DashboardLivePersonalDrawdownHeroSeries.resolve(
                .init(
                    account: account,
                    lifetimeTrades: trades,
                    ledgerEntries: [],
                    period: .init(dateRange: .all, customInterval: nil)
                )
            )
        )
        let rendered = ProfileEquityCurveChartModel.renderPoints(from: hero)
        XCTAssertEqual(rendered.count, hero.count)
        for (engine, chart) in zip(hero, rendered) {
            XCTAssertEqual(chart.tradeIndex, engine.index)
            XCTAssertEqual(chart.equity, engine.equity)
            XCTAssertEqual(chart.equityY, NSDecimalNumber(decimal: engine.equity).doubleValue)
            XCTAssertEqual(chart.drawdownFloorY, engine.drawdownFloor.map { NSDecimalNumber(decimal: $0).doubleValue })
        }
        XCTAssertLessThan(rendered[1].drawdownFloorY ?? 0, rendered[1].equityY)
    }

    private func trade(pnl: Decimal, at: String) -> Trade {
        let stamp = ISO8601DateFormatter().date(from: at) ?? Date()
        return Trade(
            id: TradeID(UUID().uuidString),
            ownerProfileID: ProfileID("11111111-1111-1111-1111-111111111111"),
            accountID: TradingAccountID("22222222-2222-2222-2222-222222222222"),
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
}