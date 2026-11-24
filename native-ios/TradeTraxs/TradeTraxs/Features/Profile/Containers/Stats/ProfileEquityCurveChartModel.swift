import Foundation

/// Shared axis model for ``ProfileEquityCurveView``, trade index or timeline (X) and one balance scale (Y).
nonisolated enum ProfileEquityCurveChartModel {
    /// Single Y plottable for equity and drawdown floor (Swift Charts uses separate scales per value name).
    static let balanceYPlottable = "Account balance"
    static let tradeXPlottable = "Trade index"
    static let timelineXPlottable = "Chart time"

    enum XAxisMode: Equatable, Sendable {
        /// Sparse trade-level series, even index spacing (pre-aggregation behavior).
        case tradeIndex
        /// Aggregated buckets positioned on the time axis.
        case timeline
    }

    struct RenderPoint: Equatable, Identifiable {
        var id: Int { index }
        /// Contiguous scrub target (0…n−1); not used as the trade-level X coordinate.
        var index: Int
        /// Plotted X for trade-level series, matches ``ProfileStatisticsMetrics/EquityPoint/index``.
        var tradeIndex: Int
        var equity: Decimal
        var equityY: Double
        var drawdownFloorY: Double?
        var date: Date?
        var periodStart: Date?
        var periodEnd: Date?
        var periodNetPnL: Decimal?
        var detailLevel: ProfileEquityCurveAggregation.DetailLevel = .trade
        var tradesInBucket: Int = 1

        /// Closing timestamp for aggregated plot placement; trade-level uses `date`.
        var plotTime: Date? {
            periodEnd ?? date
        }
    }

    static func renderPoints(
        from equityPoints: [ProfileStatisticsMetrics.EquityPoint]
    ) -> [RenderPoint] {
        ProfileEquityCurveDisplaySeries.build(from: equityPoints).renderPoints
    }

    static func yDomain(for renderPoints: [RenderPoint]) -> ClosedRange<Double> {
        var values = renderPoints.map(\.equityY)
        values.append(contentsOf: renderPoints.compactMap(\.drawdownFloorY))
        let minY = values.min() ?? 0
        let maxY = values.max() ?? 0
        if minY == maxY {
            let pad = max(abs(minY) * 0.1, 10)
            return (minY - pad)...(maxY + pad)
        }
        let pad = (maxY - minY) * 0.12
        return (minY - pad)...(maxY + pad)
    }

    static func tradeIndexDomain(for renderPoints: [RenderPoint]) -> ClosedRange<Int> {
        let maxIndex = renderPoints.map(\.tradeIndex).max() ?? 1
        let upper = max(1, maxIndex)
        let trailingSlots = tradeIndexTrailingAxisInset(maxTradeIndex: upper)
        return 0...(upper + trailingSlots)
    }

    /// Extra slots past the last trade so the terminal `MMMd` label is not clipped at the plot edge.
    private static func tradeIndexTrailingAxisInset(maxTradeIndex: Int) -> Int {
        max(1, Int(ceil(Double(max(1, maxTradeIndex + 1)) * 0.07)))
    }

    static func timelineDomain(for renderPoints: [RenderPoint]) -> ClosedRange<Date>? {
        let stamps = renderPoints.compactMap(\.plotTime)
        guard let minDate = stamps.min(), let maxDate = stamps.max(), minDate < maxDate else { return nil }
        let span = maxDate.timeIntervalSince1970 - minDate.timeIntervalSince1970
        let insets = timelineXAxisInsets(span: span)
        let start = Date(timeIntervalSince1970: minDate.timeIntervalSince1970 - insets.leading)
        let end = Date(timeIntervalSince1970: maxDate.timeIntervalSince1970 + insets.trailing)
        return start...end
    }

    /// Asymmetric domain padding sized for `MMMyy` / `MMMd` axis labels without over-shrinking the curve.
    static func timelineXAxisInsets(span: TimeInterval) -> (leading: TimeInterval, trailing: TimeInterval) {
        let leading = min(max(span * 0.04, 4 * 3_600), 86_400 * 3)
        let trailing = min(max(span * 0.07, 8 * 3_600), 86_400 * 5)
        return (leading, trailing)
    }

    static func xAxisMode(for series: ProfileEquityCurveDisplaySeries) -> XAxisMode {
        series.xAxisMode
    }

    static func nearestTradeIndex(to tradeIndex: Int, in renderPoints: [RenderPoint]) -> Int? {
        guard !renderPoints.isEmpty else { return nil }
        return renderPoints.min { lhs, rhs in
            abs(lhs.tradeIndex - tradeIndex) < abs(rhs.tradeIndex - tradeIndex)
        }?.tradeIndex
    }

    static func nearestPlotTime(to date: Date, in renderPoints: [RenderPoint]) -> Date? {
        guard !renderPoints.isEmpty else { return nil }
        return renderPoints.min { lhs, rhs in
            let left = lhs.plotTime ?? .distantPast
            let right = rhs.plotTime ?? .distantPast
            return abs(left.timeIntervalSince(date)) < abs(right.timeIntervalSince(date))
        }?.plotTime
    }

    /// Confirms floor and equity share absolute balance units at each index (no normalization).
    static func balanceSeriesAlignment(
        from equityPoints: [ProfileStatisticsMetrics.EquityPoint]
    ) -> [(index: Int, equityY: Double, floorY: Double?)] {
        renderPoints(from: equityPoints).map { ($0.index, $0.equityY, $0.drawdownFloorY) }
    }

    private static func moneyToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}