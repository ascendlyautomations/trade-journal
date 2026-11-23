import Foundation

/// Precomputed chart payload for ``ProfileEquityCurveView`` (built when input points change, not while scrubbing).
nonisolated struct ProfileEquityCurveDisplaySeries: Equatable, Sendable {
    var detailLevel: ProfileEquityCurveAggregation.DetailLevel
    var sourcePointCount: Int
    var xAxisMode: ProfileEquityCurveChartModel.XAxisMode
    var renderPoints: [ProfileEquityCurveChartModel.RenderPoint]

    static func build(from points: [ProfileStatisticsMetrics.EquityPoint]) -> ProfileEquityCurveDisplaySeries {
        let ordered = ProfileStatisticsMetrics.chartOrderedEquityPoints(points)
        let scrubPoints = ProfileEquityCurveAggregation.aggregateForDisplay(ordered)
        let level = scrubPoints.first?.detailLevel ?? scrubPoints.last?.detailLevel ?? .trade
        let render = scrubPoints.enumerated().map { offset, scrub in
            let tradeIndex = (level == .trade && offset < ordered.count) ? ordered[offset].index : offset
            return ProfileEquityCurveChartModel.RenderPoint(
                index: offset,
                tradeIndex: tradeIndex,
                equity: scrub.equity,
                equityY: NSDecimalNumber(decimal: scrub.equity).doubleValue,
                drawdownFloorY: scrub.drawdownFloor.map { NSDecimalNumber(decimal: $0).doubleValue },
                date: scrub.anchorDate,
                periodStart: scrub.periodStart,
                periodEnd: scrub.periodEnd,
                periodNetPnL: scrub.periodNetPnL,
                detailLevel: scrub.detailLevel,
                tradesInBucket: scrub.tradesInBucket
            )
        }
        let canUseTimeline = level != .trade
            && scrubPoints.allSatisfy { $0.periodEnd != nil || $0.anchorDate != nil }
            && ProfileEquityCurveChartModel.timelineDomain(for: render) != nil
        return ProfileEquityCurveDisplaySeries(
            detailLevel: level,
            sourcePointCount: ordered.count,
            xAxisMode: canUseTimeline ? .timeline : .tradeIndex,
            renderPoints: render
        )
    }

    var finalEquity: Decimal? {
        renderPoints.last?.equity
    }
}