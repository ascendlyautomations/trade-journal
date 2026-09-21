import Foundation
import OSLog

#if DEBUG
nonisolated enum TradeSummaryLegacyTelemetry {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradeSummary")

    static func legacyFullTradePath(context: String, tradeID: TradeID? = nil) {
        let id = tradeID?.rawValue ?? "unknown"
        log.debug(
            "[TradeSummary][LegacyFullTradePath] context=\(context, privacy: .public) tradeID=\(id, privacy: .public)"
        )
    }
}

nonisolated enum TradeDetailAuthorityTelemetry {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradeDetail")

    static func authorityViolation(context: String, tradeID: TradeID) {
        log.debug(
            "[TradeDetail][AuthorityViolation] context=\(context, privacy: .public) tradeID=\(tradeID.rawValue, privacy: .public)"
        )
    }
}
#endif
