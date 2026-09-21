#if DEBUG
import Foundation
import OSLog

nonisolated enum TradeSummaryFeedTelemetry {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradeSummary.Feed")

    static func recordDecode(tradeCount: Int, skipped: Int) {
        log.info(
            "[TradeSummary][FeedDecode] count=\(tradeCount, privacy: .public) skipped=\(skipped, privacy: .public)"
        )
    }

    static func recordCacheHit(entryCount: Int) {
        log.info("[TradeSummary][FeedCacheHit] count=\(entryCount, privacy: .public)")
    }

    static func recordDetailBoundary(action: String, tradeID: String) {
        log.info(
            "[TradeSummary][DetailBoundary] surface=feed action=\(action, privacy: .public) tradeID=\(tradeID, privacy: .public)"
        )
    }
}
#endif
