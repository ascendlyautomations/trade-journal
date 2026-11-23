import Foundation
import OSLog

#if DEBUG
/// Verifies hero chart equity + floor share one live replay (same account balance baseline).
nonisolated enum LivePersonalDrawdownChartAudit {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "LivePersonalDrawdownChart"
    )

    static func logHeroSeries(account: TradingAccount, points: [ProfileStatisticsMetrics.EquityPoint]) {
        let starting = LivePersonalDrawdownEngine.resolvedStartingBalance(for: account)
        let stored = account.livePersonalDrawdown
        let limit = stored?.limitAmount
        let limitType = stored?.limitType
        let firstEquity = points.first?.equity
        let firstFloor = points.first?.drawdownFloor
        let floorCalc: String = {
            guard let starting, let limit, limit > 0 else { return "n/a" }
            if limitType == .fixed { return "baseline(\(starting)) − fixedLimit(\(limit))" }
            return "openingHWM(\(starting)) − trailingLimit(\(limit))"
        }()
        logger.debug(
            """
            liveDrawdown.chart account=\(account.id.rawValue, privacy: .public) \
            account_size=\(starting.map { "\($0)" } ?? "nil", privacy: .public) \
            max_drawdown=\(limit.map { "\($0)" } ?? "nil", privacy: .public) \
            drawdown_type=\(limitType.map { "\($0)" } ?? "nil", privacy: .public) \
            pointCount=\(points.count, privacy: .public) \
            firstVisibleEquity=\(firstEquity.map { "\($0)" } ?? "nil", privacy: .public) \
            firstVisibleFloor=\(firstFloor.map { "\($0)" } ?? "nil", privacy: .public) \
            firstFloorCalc=\(floorCalc, privacy: .public) \
            pipeline=DashboardLivePersonalDrawdownHeroSeries
            """
        )
        for (index, point) in points.prefix(5).enumerated() {
            if let floor = point.drawdownFloor, point.equity < floor {
                logger.debug(
                    "liveDrawdown.chart point[\(index, privacy: .public)] equity=\(point.equity, privacy: .public) floor=\(floor, privacy: .public) breachOrFloorAboveEquity"
                )
            }
        }
    }
}
#endif