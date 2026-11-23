import Foundation

/// Presentation model for ``ProfileEquityCurveView`` — enables regression tests on the chart pipeline.
nonisolated enum ProfileEquityCurvePresentation {
  struct ChartPoint: Equatable {
    var index: Int
    var equity: Decimal
    var drawdownFloor: Decimal?
    var date: Date?
  }

  static func chartPoints(
    from equityPoints: [ProfileStatisticsMetrics.EquityPoint]
  ) -> [ChartPoint] {
    let ordered = ProfileStatisticsMetrics.chartOrderedEquityPoints(equityPoints)
    return ordered.map {
      ChartPoint(
        index: $0.index,
        equity: $0.equity,
        drawdownFloor: $0.drawdownFloor,
        date: $0.date
      )
    }
  }
}