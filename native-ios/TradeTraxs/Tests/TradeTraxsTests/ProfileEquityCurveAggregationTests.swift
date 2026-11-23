import XCTest
@testable import TradeTraxs

final class ProfileEquityCurveAggregationTests: XCTestCase {
    func testSparseYearKeepsTradeLevel() {
        let points = (0..<5).map { makePoint(index: $0, equity: 50_000 + Decimal($0 * 100), dayOffset: $0 * 60) }
        let series = ProfileEquityCurveDisplaySeries.build(from: points)
        XCTAssertEqual(series.detailLevel, .trade)
        XCTAssertEqual(series.renderPoints.count, 5)
        XCTAssertEqual(series.finalEquity, points.last?.equity)
    }

    func testDenseSeriesAggregatesByDay() {
        var points: [ProfileStatisticsMetrics.EquityPoint] = [
            makePoint(index: 0, equity: 50_000, dayOffset: 0, floor: 48_000)
        ]
        for offset in 1...40 {
            points.append(
                makePoint(
                    index: offset,
                    equity: 50_000 + Decimal(offset * 10),
                    dayOffset: offset / 3,
                    floor: 48_000 + Decimal(offset)
                )
            )
        }
        let series = ProfileEquityCurveDisplaySeries.build(from: points)
        XCTAssertEqual(series.sourcePointCount, 41)
        XCTAssertLessThan(series.renderPoints.count, 20)
        XCTAssertEqual(series.finalEquity, points.last?.equity)

        let lastRender = series.renderPoints.last!
        XCTAssertEqual(lastRender.equity, points.last?.equity)
        XCTAssertEqual(lastRender.drawdownFloorY, points.last?.drawdownFloor.map { NSDecimalNumber(decimal: $0).doubleValue })
    }

    func testDrawdownFloorMatchesEquityBucketEnd() {
        let calendar = Calendar.current
        let day0 = calendar.startOfDay(for: Date())
        var points: [ProfileStatisticsMetrics.EquityPoint] = [
            ProfileStatisticsMetrics.EquityPoint(index: 0, equity: 50_000, date: day0, drawdownFloor: 48_000),
        ]
        for offset in 1...35 {
            points.append(
                ProfileStatisticsMetrics.EquityPoint(
                    index: offset,
                    equity: 50_000 + Decimal(offset * 10),
                    date: day0,
                    drawdownFloor: 48_000 + Decimal(offset)
                )
            )
        }
        let series = ProfileEquityCurveDisplaySeries.build(from: points)
        XCTAssertEqual(series.renderPoints.last?.equity, points.last?.equity)
        XCTAssertEqual(
            series.renderPoints.last?.drawdownFloorY,
            points.last?.drawdownFloor.map { NSDecimalNumber(decimal: $0).doubleValue }
        )
    }

    func testDisplayIndicesAreContiguousForScrub() {
        let points = (0..<60).map { makePoint(index: $0, equity: 40_000 + Decimal($0), dayOffset: $0) }
        let series = ProfileEquityCurveDisplaySeries.build(from: points)
        XCTAssertEqual(series.renderPoints.map(\.index), Array(0..<series.renderPoints.count))
    }

    func testSparseSeriesUsesTradeIndexAxis() {
        let points = (0..<12).map { makePoint(index: $0 * 2, equity: 40_000 + Decimal($0), dayOffset: $0 * 28) }
        let series = ProfileEquityCurveDisplaySeries.build(from: points)
        XCTAssertEqual(series.xAxisMode, .tradeIndex)
        XCTAssertEqual(
            series.renderPoints.map(\.tradeIndex),
            Array(0..<series.renderPoints.count)
        )
    }

    func testDenseSeriesUsesTimelineAxis() {
        var points: [ProfileStatisticsMetrics.EquityPoint] = [
            makePoint(index: 0, equity: 50_000, dayOffset: 0)
        ]
        for offset in 1...80 {
            points.append(
                makePoint(
                    index: offset,
                    equity: 50_000 + Decimal(offset * 5),
                    dayOffset: offset / 4
                )
            )
        }
        let series = ProfileEquityCurveDisplaySeries.build(from: points)
        XCTAssertEqual(series.xAxisMode, .timeline)
        let stamps = series.renderPoints.compactMap(\.plotTime)
        XCTAssertEqual(stamps, stamps.sorted())
        XCTAssertLessThan(series.renderPoints.count, points.count)
    }

    private func makePoint(
        index: Int,
        equity: Decimal,
        dayOffset: Int,
        floor: Decimal? = nil
    ) -> ProfileStatisticsMetrics.EquityPoint {
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return ProfileStatisticsMetrics.EquityPoint(
            index: index,
            equity: equity,
            date: date,
            drawdownFloor: floor
        )
    }
}