#if DEBUG
import Foundation
import OSLog

nonisolated enum TradeSummaryCalendarTelemetry {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradeSummary.Calendar")

    static func recordDayDecode(tradeCount: Int, payloadBytes: Int?, elapsedMs: Int?) {
        log.info(
            "[TradeSummary][CalendarDayDecode] count=\(tradeCount, privacy: .public) bytes=\(payloadBytes ?? -1, privacy: .public) ms=\(elapsedMs ?? -1, privacy: .public)"
        )
    }

    static func recordDayCacheHit(tradeCount: Int, dayKey: String) {
        log.info(
            "[TradeSummary][CalendarDayCacheHit] day=\(dayKey, privacy: .public) count=\(tradeCount, privacy: .public)"
        )
    }

    static func recordDetailBoundary(action: String, tradeID: String) {
        log.info(
            "[TradeSummary][DetailBoundary] surface=calendar action=\(action, privacy: .public) tradeID=\(tradeID, privacy: .public)"
        )
    }
}
#endif
